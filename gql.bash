#!/usr/bin/env bash

##############################################################################

declare -Ar _GQL_OP_MAPPINGS=(
    [get]='query'
    [q]='query'
    [m]='mutation'
    [mut]='mutation'
    [do]='mutation'
    [s]='subscription'
    [sub]='subscription'
    [wait]='subscription'
    [iter]='subscription'
)

function gql
{
    gql.setup "${GQL_PROFILE:-default}"
    local OPTARG OPTIND OPT
    local GQL_URL="${GQL_URL}"
    local SHOW_QUERY SHOW_JQ SHOW_STRUCT SHOW_OUTPUT DEBUG_FORMATTER RAW_JSON
    local SHOW_HEADERS
    
    while getopts 'u:QJFSORPHN' OPT
    do
        case "$OPT" in
        u) GQL_URL="$OPTARG";;
        Q) SHOW_QUERY=1;;
        J) SHOW_JQ=1;;
        F) DEBUG_FORMATTER=1;;
        H) SHOW_HEADERS=1;;
        S) SHOW_STRUCT=1;;
        O) SHOW_OUTPUT=1;;
        R) RAW_JSON=1;;
        P) RAW_JSON=pretty;;
        N) SHOW_OUTPUT=none;;
        esac
    done
    
    shift $(( OPTIND - 1 ))
    
    local op="$1"; shift
    local mapped="${_GQL_OP_MAPPINGS[${op,}]:-${op,,}}"
    case "${mapped}" in
    
    query)
        local -A parsed
        local gql
        gql.build parsed "$@" 
        gql.dump parsed query gql
        gql.exec "$gql" | gql.output parsed
        ;;
    
    '')
        {
            echo "USAGE: gql [op]"
        } >&2
        exit 65;;
        
    *)
        echo >&2 "Invalid op '$op'"
        exit 1;;

    esac
}

function gql.setup
{
    declare -gn "_GQLCFG_${GQL_PROFILE:-_$1}"
}

##############################################################################

function gql.build
{
    local -n _dest="$1"; shift || gql.required dest
    local -a _args=( "$@" )
    local -i _idx=0 _nargs=${#_args[@]}
    local prefix _strip_prefix
    local -n _outputs="_dest[$prefix:outputs]"
    local -n _tables="_dest[$prefix:tables]"
    _gql_build '' ''
    if [ "$SHOW_STRUCT" ]
    then
        local field
        for field in "${!_dest[@]}"
        do
            echo -e "$field\t${_dest["$field"]}"
        done | sort
    fi
}

function _gql_build
{
    local node="$1"; shift || gql.required node
    local prefix="$1"; shift || gql.required prefix
    local -n _params="_dest[$prefix:args]" _paramstr="_dest[$prefix:argstr]"
    local -n _fields="_dest[$prefix:fields]" _fieldstr="_dest[$prefix:fieldstr]"
  
    _gql_build_params "$@"
}

function _gql_build_params
{ 
    while [ $_idx -lt $_nargs ]
    do
        local arg="${_args[$_idx]}"
        case "$arg" in
        '[')
            local -n _outputs="_dest[$prefix:outputs]"
            _tables+="${_tables:+ }$prefix"
            _dest["$prefix:format"]='table'
            ;&

        '{{')
            local _strip_prefix="$prefix."
            ;&
        
        '{')
            _idx+=1
            _gql_build_fields "$@"
            return
            ;;
            
        ']' | '}' | '}}')
            return
            ;;
        
        *)
            local name value="${arg#*=}"
            if [ "$value" != "$arg" ]
            then
                name="${arg%%=*}"
                value="${value/\"//\\\"}"
                value="${value/\n//\\n}"
                value="\"$value\""
            else
                value="${arg#*:}"
                if [ "$value" != "$arg" ]
                then
                    name="${arg%%:*}"
                fi
            fi
            
            if [ "$name" ]
            then
                if [ "${name#-}" != "$name" ]
                then
                    _dest["$prefix:$name"]="$value"
                elif [ "$value" ]
                then
                    if [ $# = 0 ]
                    then
                        name="\$${name#\$}"
                    fi
                    _params+="${_params:+ }${name}"
                    _paramstr+="${_paramstr:+, }${name}: ${value}"
                else
                    # Alias decalration, handled in fields...
                    return
                fi                    
            else
                #_gql_build_fields
                return
            fi
            _idx+=1
            ;;
        esac
        
    done
}

function _gql_build_fields
{
    local alias
    while [ $_idx -lt $_nargs ]
    do
        local arg="${_args[$_idx]}"
        case "$arg" in
        '{{' | '{' | '[')
            # This is an error...
            _idx+=1
            return
            ;;
            
        '}' | ']' | '}}')
            _idx+=1
            break
            ;;
        
        *)
            if [ "${arg%:}" = "$arg" ]
            then
                _idx+=1
                local child="${alias:-$arg}"
                local stripped="${prefix#$_strip_prefix}"
                if [ "$stipped" != "$prefix" ]
                then
                    _dest["$prefix.$child:label"]="$stripped${stripped:+.}$child"
                fi
                _fields+="${_fields:+ }${child}"
                _gql_build "$child" "$prefix.$child" "$child" "$@"
                if [ "$alias" ]
                then
                    _dest["$prefix.$child:alias-for"]="$arg"
                    alias=
                fi
                if [ ! "${_dest["$prefix.$child":fields]}" ]
                then
                    _outputs+="${_outputs:+ }$prefix.$child"
                fi
            else
                _idx+=1
                alias="${arg%:}"
            fi
            ;;
        esac            
    done
}

##############################################################################

function gql.exec
{
    local gql="$1"; shift || gql.required 'graphql query'
    
    if [ "$SHOW_QUERY" ]
    then
        echo >&2 "$gql"
    fi
    
    "${GQL_AGENT:-gql.curl}" "$gql" "$GQL_URL"
}

function gql.curl
{
    local gql="$1"; shift || gql.required 'graphql query'
    local url="$1"; shift || gql.required 'graphql url'
    echo '{}' | jq \
        --arg query "$gql" \
    '{
        "query": $query
    }' |
    # tee /dev/stderr |
    curl -s -X POST --data-binary @- \
        -H 'Content-Type: application/json' \
        "$url"
}

##############################################################################

function gql.dump
{
    local _src="$1"; shift || gql.required source
    local op="$1"; shift || gql.required operation
    local dest="$1"; shift
    local -a terms
    
    gql.format "$_src" terms "$op"
    if [ "$dest" ]
    then
        local -n _dest="$dest"
        _dest="${terms[@]}"
    else
        echo "${terms[@]}"
    fi        
}

function gql.format
{
    local -n _src="$1"; shift || gql.required source
    local -n _dest="$1"; shift || gql.required destination
    local node="$1"; shift || gql-required node
    local scope="$1"; shift

    local alias_for="${_src["$scope:alias-for"]}"
    if [ "$alias_for" ]
    then
        _dest+=( "$node: $alias_for" )
    else
        _dest+=( "$node" )
    fi
    
    local argstr="${_src["$scope:argstr"]}"
    if [ "$argstr" ]
    then
        _dest+=( '(' "$argstr" ')' )
    fi
    
    local fields="${_src["$scope:fields"]}"
    if [ "$fields" ]
    then
        _dest+=( '{' )
        
        local field
        for field in $fields
        do
            gql.format "${!_src}" "${!_dest}" "$field" "$scope.$field"
        done
        
        _dest+=( '}' )
    fi
}

##############################################################################

function gql.output
{
    if [ "$SHOW_OUTPUT" -a "$SHOW_OUTPUT" != none ]
    then
        tee /dev/stderr
    else
        cat -
    fi |
    
    "gql.format.${GQL_FORMATTER:-jq}" "$@" |
    if [ "$SHOW_OUTPUT" != none ]
    then
        cat -
    else
        cat >/dev/null
    fi
}

function gql.format.jq
{
    local jq
    local -n config="$1"; shift || gql.required config 
    
    local outputs="${config[':outputs']}"
    if [ "$outputs" ]
    then
        local output
        for output in $outputs
        do
            local label="${config["$output:label"]:-$output}"
            jq+="${jq:+,}([\"$label\",.data$output]|@tsv)"
        done
    fi        
        
    local table_prefix
    for table_prefix in ${config[':tables']}
    do
        local -a headers
        local table_field table_jq
        for table_field in ${config["$table_prefix:outputs"]}
        do
            table_field="${table_field#$table_prefix}"
            table_jq+="${table_jq:+,}$table_field"
            
            headers+=( "${config["$table_field:label"]:-$table_field}" )
        done
        local header_jq header
        if [ "$SHOW_HEADERS" ]
        then
            for header in "${headers[@]}"
            do
                header_jq+="${header_jq:+,}\"$header\""
            done
            header_jq="[$header_jq],"
        fi            
        jq+="${jq:+,}(($header_jq(.data$table_prefix[]|[$table_jq]))|@tsv)"
    done
    
    if [ "$DEBUG_FORMATTER" -o "$SHOW_JQ" ]
    then
        echo "JQ: $jq" >&2
    fi
    
    if [ "$RAW_JSON" = '' -a "$jq" ]
    then
        jq -r "
            if has(\"errors\")
            then
                .errors[] |
                (
                    error(.message)
                )
            else
                ($jq)
            end                
        "
    elif [ "$RAW_JSON"=pretty -o -t 1 ]
    then
        jq .
    else
        cat -
    fi            
}

##############################################################################

function gql.required
{
    gql.fatal required-arg missing "$@" in "$(caller 1)"
}

function gql.fatal
{
    local type="$1"; shift
    echo >&2 "$@"
    exit 1
}

##############################################################################

( return 0 2>/dev/null ) && gql_setup "$@" || gql "$@"
