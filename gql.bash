#!/usr/bin/env bash

##############################################################################
##############################################################################

function gql
{
    local OPTIND OPTARG OPT
    local op=query 
    local GQL_URL="${GQL_URL}" 
    local GQL_PROFILE="${GQL_PROFILE}"
    local GQL_LOG_LEVEL="${GQL_LOG_LEVEL:-0}"
    local dry_run
    
    while getopts 'du:p:qmsO:n' OPT
    do
        case "$OPT" in
        d) GQL_LOG_LEVEL=-2;;
        q) op=query;;
        m) op=mutatiion;;
        s) op=subscription;;
        O) op="$OPTARG";;
        u) GQL_URL="$OPTARG";;
        p) GQL_PROFILE="$OPTARG";;
        n) dry_run=1;;
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
        
            local -A _gql_doc
            gql.build _gql_doc "$op" data "$@"
            gql.format _gql_doc query |
            tee /dev/stderr |
            if [ "$dry_run" ]
            then
                cat -
            else
                gql.agent "$GQL_URL" 
            fi
            ;;
            
        *)
            _gql_usage_error "Op '$op' is not valid"
            ;;
    esac
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
    local buildpath="${1:-$docpath}"
    
    # These two references will be based on the value of $buildpath upon use.
    local -n paramstr='_doc[$buildpath:paramstr]'
    local -n fields='_doc[$buildpath:fields]'
    
    _doc["${docpath}:node"]="${docpath##*.}"

    while [ $_idx -lt $_nargs ]
    do
        local arg="${_args[$_idx]}"
        case "$arg" in
        '{')
            _idx+=1
            _gql_build "$buildpath" "$buildpath"
            ;;
            
        '}')
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
                    value="${value//\n/\\n}"
                    value="\"$value\""
                else                    
                    value="${arg#*:}"
                    if [ "$arg" != "$value" ]
                    then
                        name="${arg%%:*}"
                        _gql_dump name value
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
                    while true
                    do
                        suffix="${arg#*.}"
                        if [ "$suffix" = "$arg" ]
                        then
                            break
                        else
                            {
                                node="${arg%%.*}"
                                if [ ! "${_doc["$buildpath.$node:fields"]}" ]
                                then
                                    fields+="${fields:+ }$node"
                                fi                                    
                                buildpath+=".$node"
                                _doc["$buildpath:node"]="$node"
                                arg="$suffix"
                            }
                        fi
                    done
                    fields+="${fields:+ }$arg"
                    _doc["$buildpath.$arg:node"]="$arg"
                    buildpath="$buildpath.$arg"
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
    "${GQL_AGENT:-gql.agent.curl}" "$@"
}

function gql.agent.curl
{
    local OPTIND OPTARG OPT
    local url="${GQL_URL}"
    local gql='-'
    
    while getopts 'u:' OPT
    do
        case "$OPT" in
        u) url="$OPTARG";;
        d) gql="$OPTARG";;
        esac
    done
    shift $(( OPTIND - 1 ))
    
    if [ "$gql" = - ]
    then
        gql="$(cat -)"
    fi
    
    echo {} | jq --arg gql "$gql" '
    {
        "query": $gql
    }' |
    curl \
        -X POST \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        --data-binary @- \
        "$url"
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
            echo "$@"
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

##############################################################################

function _gql_internal_error
{
    _gql_fatal 63 "$@"
}

function _gql_usage_error
{
    _fql_fatal 65 "$@"
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

( return 0 2>/dev/null ) || gql "$@"
