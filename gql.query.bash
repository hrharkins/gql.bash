
##############################################################################
##############################################################################

function gql:op:query
{
    local -A _gql_doc
    gql:build-document _gql_doc query "$@"
    gql:format-document _gql_doc | gql:do - ${GQL[vars]:-}
}

function gql:op:mutation
{
    local -A _gql_doc
    gql:build-document _gql_doc mutation "$@"
    gql:format-document _gql_doc | gql:do - ${GQL[vars]:-}
}

##############################################################################
##############################################################################

function gql:op:do
{
    local doc="$1"; shift || gql:required doc 'GQL document'
    gql:do "$doc" ${GQL[vars]:-} "$@"
}

##############################################################################

function gql:do
{
    local gql="$1"; shift || gql:required gql 'gql document, -,  or @fileref'
    local varstr=
    local -a args
    local arg name value
    
    for arg in "$@"
    do
        value="${arg#*=}"
        if [ "$value" = "$arg" ]
        then
            value="${arg#*:}"
            if [ "$value" = "$arg" -o ! "$value" ]
            then
                name=
            else
                name="${arg%%:*}"
            fi
        else
            name="${arg%%=*}"
            value="\"${value//\"/\\\"}\""
        fi
        
        if [ "$name" ]
        then
            varstr+="${varstr:+, }\"$name\":\$$name"
            args+=( --argjson "$name" "$value" )
        fi
    done
    
    if [ "$gql" = - ]
    then
        cat "$gql"
    else
        echo "$gql"
    fi | 
        jq -Rs "${args[@]}" '{ "query": ., "variables": {'"$varstr"'} }' |
        gql:agent:"${GQL[agent]:-curl}"
}
