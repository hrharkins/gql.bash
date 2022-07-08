#!/usr/bin/env bash

##############################################################################
##############################################################################

function gql
{
    #set -eu
    
    local OPTIND OPTARG OPT
    local op=query
    local GQL_URL="${GQL_URL}"
    local GQL_PROFILE="${GQL_PROFILE:-}"
    local GQL_LOG_LEVEL="${GQL_LOG_LEVEL:-0}"
    local GQL_SSO="${GQL_SSO}"
    local dry_run gql
    local GQL_SSO
    
    while getopts 'dDu:p:qmsO:nG:' OPT
    do
        case "$OPT" in
        d) GQL_LOG_LEVEL=-2;;
        q) op=query;;
        m) op=mutation;;
        s) op=subscription;;
        O) op="$OPTARG";;
        u) GQL_URL="$OPTARG";;
        p) GQL_PROFILE="$OPTARG";;
        n) dry_run=1;;
        G) gql="$OPTARG";;
        D) dry_run=doc;;
        esac
    done
    shift $(( OPTIND - 1 ))

    local -A _gql_config
    _gql_copy_dict "${GQL_PROFILE:-GQL_CONFIG}" _gql_config
    
    if [ "$GQL_URL" ]
    then
        _gql_config[url]="$GQL_URL"
    fi

    case "$op" in
        query|mutation|subscription)
            {
                local -A _gql_doc
                if [ ! "${gql:-}" ]
                then
                    gql.build _gql_doc "$op" data "$@"
                    gql=$( gql.format _gql_doc "$op" )
                fi
                if [ "$dry_run" = doc ]
                then
                    declare -p _gql_doc
                elif [ "$dry_run" ]
                then
                    echo "$gql"
                else
                    _gql_verbose "QUERY:\n$gql\n"
                    echo "$gql" |
                        gql.agent "$GQL_URL" |
                        gql.output-doc _gql_doc "$op"
                fi
            }
            ;;
            
        schema)
            gql.schema | jq .
            ;;

        *)
            _gql_usage_error "Op '$op' is not valid"
            ;;
    esac
}

##############################################################################
##############################################################################

function gql.query
{
    local -A _gql_doc
    gql.build _gql_doc "$op" data "$@"
    gql.format _gql_doc query | gql.agent "$GQL_URL"
}

##############################################################################
##############################################################################

function gql.build
{
    local -n _doc="$1"; shift || _gql_required 'gql document variable reference'
    local docpath="$1"; shift || _gql_required 'gql document path'
    local datapath="$1"; shift || _gql_required 'gql result data path'

    local -a _args=( "$@" )
    local -i _idx=0 _nargs="${#_args[@]}"

    _gql_build "$docpath" "$datapath"
}

function _gql_build
{
    local docpath="$1"; shift || _gql_required 'gql document path'
    local datapath="$1"; shift || _gql_required 'gql result data path'
    local buildpath="${1:-$docpath}"; shift
    local builddata="${1:-$datapath}"; shift
    _doc["${docpath}:datapath"]="$datapath"

    # These two references will be based on the value of $buildpath upon use.
    local -n paramstr='_doc[$buildpath:paramstr]'
    local -n fields='_doc[$buildpath:fields]'

    _doc["${docpath}:node"]="${docpath##*.}"

    while [ $_idx -lt $_nargs ]
    do
        local arg="${_args[$_idx]}"
        case "$arg" in
        '[')
            _doc["${buildpath}:mode"]=table
            ;&

        '{')
            _idx+=1
            _gql_build "$buildpath" "$builddata"
            ;;

        '}' | ']')
            _idx+=1
            return
            ;;

        *)
            {
                local node suffix name value="${arg#*=}"
                _idx+=1

                if [ "$arg" != "$value" ]
                then
                    name="${arg%%=*}"
                    value="${value//\"/\\\"}"
                    #value="${value//\n/\\n}"
                    value="\"$value\""
                else
                    value="${arg#*:}"
                    if [ "$arg" != "$value" ]
                    then
                        name="${arg%%:*}"
                    fi
                fi

                if [ "$name" ]
                then
                    if [ "$value" ]
                    then
                        paramstr+="${paramstr:+, }$name: $value"
                    else
                        : alias...
                    fi
                else
                    buildpath="$docpath"
                    builddata="$datapath"
                    while true
                    do
                        suffix="${arg#*.}"
                        if [ "$suffix" = "$arg" ]
                        then
                            break
                        else
                            {
                                node="${arg%%.*}"
                                arg="$suffix"
                                if [ ! "${_doc["$buildpath.$node:fields"]}" ]
                                then
                                    fields+="${fields:+ }$node"
                                fi
                                buildpath+=".$node"
                                builddata+=".$node"
                                _doc["$buildpath:node"]="$node"
                            }
                        fi
                    done

                    fields+="${fields:+ }$arg"
                    _doc["$buildpath.$arg:node"]="$arg"
                    buildpath+=".$arg"
                    builddata+=".$arg"
                    _doc["${buildpath}:datapath"]="$builddata"
                fi
            }
            ;;
        esac
    done
}

##############################################################################
##############################################################################

function gql.format
{
    local -n _doc="$1"; shift || _gql_required 'gql document variable reference'
    local docpath="$1"; shift || _gql_required 'gql document path'
    local prefix="$1"; shift
    local indent="${1:-    }"; shift

    _gql_format "$docpath" "$prefix"
}

function _gql_format
{
    local docpath="$1"; shift || _gql_required 'gql document path'
    local prefix="$1"; shift

    echo -n "$prefix${_doc["$docpath":node]}"

    local paramstr="${_doc["$docpath":paramstr]}"
    if [ "$paramstr" ]
    then
        echo -n "($paramstr)"
    fi

    local field fields="${_doc["$docpath":fields]}"
    if [ "$fields" ]
    then
        echo " {"
        for field in ${_doc["$docpath":fields]}
        do
            _gql_format "$docpath.$field" "$prefix$indent"
        done
        echo "$prefix}"
    else
        echo
    fi
}

##############################################################################
##############################################################################

function gql.agent
{
    local -A _headers
    
    gql.sso.headers _headers
    
    "${GQL_AGENT:-gql.agent.curl}" -H _headers "$@" |
        jq '
            if has("errors")
            then
                ( .errors[] | [ error(.message) ] )
            else
                ( . )
            end
        '
}

function gql.agent.curl
{
    local OPTIND OPTARG OPT
    local url="${GQL_URL}"
    local gql='-'
    local -n headers
    local -a curlopts

    while getopts 'u:H:' OPT
    do
        case "$OPT" in
        u) url="$OPTARG";;
        d) gql="$OPTARG";;
        H) headers="$OPTARG";;
        O) curlopts+=( "$OPTARG" );;
        esac
    done
    shift $(( OPTIND - 1 ))

    if [ "$gql" = - ]
    then
        gql="$(cat -)"
    fi
    
    local header
    for header in "${!headers[@]}"
    do
        curlopts+=( -H "$header: ${headers[$header]}" )
    done
    
    echo {} | jq --arg gql "$gql" '
    {
        "query": $gql
    }' |
    curl -s \
        -X POST \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        "${curlopts[@]}" \
        --data-binary @- \
        "$url"
}

##############################################################################

function gql.sso.headers
{
    local _sso_hdrs_var="$1"; shift || _gql_required 'headers dictionary'
    
    if [ "$GQL_SSO_METHOD" ]
    then
        gql.sso.${GQL_SSO}.headers "${_sso_hdrs_var}"
    fi
}

function gql.sso.oauth.headers
{
    local -n _sso_hdrs="$1"; shift || _gql_required 'headers dictionary'
    local bearer="${GQL_OAUTH_TOKEN}"
    if [ ! "$bearer" ]
    then
        local url="${GQL_OAUTH_URL}"
        local client_id="${GQL_OAUTH_CLIENT_ID}"
        local secret="${GQL_OAUTH_SECRET}"
        
        if [ "$url" -a "$client_id" -a "$secret" ]
        then
            local token_type created_at expires_in 
            read token_type bearer created_at expires_in  < <(
                _gql_debug "Attempting to get bearer token from '$url' via '$client_id'"
                curl -s \
                    --request POST \
                    -H 'Content-type: application/json' \
                    -H 'Accept: application/json' \
                    "$url?grant_type=client_credentials&client_id=$client_id&client_secret=$secret" |
                jq -r '
                [
                    .token_type, 
                    .access_token, 
                    .created_at, 
                    .expires_in
                ]|@tsv' 
            )
            _gql_debug "Got bearer token $bearer"
        fi
    fi
    
    _sso_hdrs['Authorization']="Bearer $bearer"
}

##############################################################################
##############################################################################

function gql.output
{
    if [ $# -gt 1 ]
    then
        _gql_debug_cmd "gql.output.${GQL_OUTPUT:-jq}" "$@" |
        if [ ! -p 1 ] && command -v column &> /dev/null
        then
            column -t -s '	'
        else
            cat -
        fi
    elif [ -t 1 ]
    then
        jq .
    else
        cat -
    fi
}

function gql.output-doc
{
    local -n _doc="$1"; shift || _gql_required 'gql parsed document'
    local docpath="$1"; shift || _gql_required 'gql root path'
    local -a _outputs

    _gql_outputs_from_doc "$docpath"

    gql.output "${_outputs[@]}"
}

function _gql_outputs_from_doc
{
    local path="$1"; shift || _gql_required 'document path'
    local prefix="$1"

    local mode="${_doc[$path:mode]}"
    local datapath="${_doc[$path:datapath]}"

    if [ "$mode" = 'table' ]
    then
        _outputs+=( ".$datapath[" )
        prefix="$datapath."
    fi

    local fields="${_doc[$path:fields]}"
    if [ "$fields" ]
    then
        local field
        for field in $fields
        do
            _gql_outputs_from_doc "$path.$field" "$prefix"
        done
    else
        _outputs+=( ".${datapath#$prefix}" )
    fi

    if [ "$mode" = 'table' ]
    then
        _outputs+=( ']' )
    fi

}

##############################################################################

function gql.output.jq
{
    local jqexpr
    _gql_make_jql "$@"
    _gql_dump jqexpr

    jq -r "($jqexpr)"
}

function _gql_make_jql
{
    local term comma

    for term in "$@"
    do
        if [ "${term%[}" != "$term" ]
        then
            jqexpr+="$comma($term]|["
            comma=
        elif [ "$term" = ']' ]
        then
            jqexpr+=']|@tsv)'
            comma=,
        else
            jqexpr+="$comma$term"
            comma=,
        fi
    done
}

##############################################################################
##############################################################################

function _gql_log
{
    local -i level="$1"; shift || _gql_required 'log level'
    if [ $level -ge ${GQL_LOG_LEVEL:-0} ]
    then
        if [ $# -gt 0 ]
        then
            echo -e "$@"
        else
            cat -
        fi >&2
    elif [ $# = 0 ]
    then
        cat - >/dev/null
    fi
}

##############################################################################

function _gql_debug         { _gql_log -2 "$@" at "$(caller 0)"; }
function _gql_debug_raw     { _gql_log -2 "$@"; }
function _gql_verbose       { _gql_log -1 "$@"; }
function _gql_info          { _gql_log  0 "$@"; }
function _gql_warning       { _gql_log  1 "$@"; }
function _gql_error         { _gql_log  2 "$@"; }

function _gql_fatal
{
    local -i exit_code="$1"; shift || _gql_required 'exit code'
    _gql_log 9999 "$@"
    exit $exit_code
}

function _gql_dump
{
    _gql_debug_raw ""
    _gql_debug_raw "At $(caller 0):"
    local _var
    for _var in "$@"
    do
        declare -p "$_var"
    done | _gql_debug_raw
}

function _gql_debug_cmd
{
    _gql_debug_raw "Running:\n    ${@@Q}"
    "$@"; local rv=$?
    _gql_debug_raw "    ... returned $rv"
    return $rv
}

##############################################################################

function _gql_internal_error
{
    _gql_fatal 63 "$@"
}

function _gql_usage_error
{
    _gql_fatal 65 "$@"
}

function _gql_required
{
    _gql_internal_error "$(caller 0) requires '$1'${@:+: }$@ from $(caller 1)"
}

##############################################################################
##############################################################################

function _gql_copy_dict
{
    local -n src="$1"; shift || _gql_required 'dict copy source'
    local -n dest="$1"; shift || _gql_required 'dict copy source'
    local key
    for key in "${!src[@]}"
    do
        dest["$key"]="${src[$key]}"
    done
}

##############################################################################
##############################################################################

function gql.schema
{
    echo '
    fragment FullType on __Type {
      kind
      name
      fields(includeDeprecated: true) {
        name
        args {
          ...InputValue
        }
        type {
          ...TypeRef
        }
        isDeprecated
        deprecationReason
      }
      inputFields {
        ...InputValue
      }
      interfaces {
        ...TypeRef
      }
      enumValues(includeDeprecated: true) {
        name
        isDeprecated
        deprecationReason
      }
      possibleTypes {
        ...TypeRef
      }
    }
    fragment InputValue on __InputValue {
      name
      type {
        ...TypeRef
      }
      defaultValue
    }
    fragment TypeRef on __Type {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                  ofType {
                    kind
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    query IntrospectionQuery {
      __schema {
        queryType {
          name
        }
        mutationType {
          name
        }
        types {
          ...FullType
        }
        directives {
          name
          locations
          args {
            ...InputValue
          }
        }
      }
    }' | gql.agent
}

##############################################################################
##############################################################################

( return 0 2>/dev/null ) || gql "$@"
