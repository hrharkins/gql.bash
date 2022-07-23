
##############################################################################
##############################################################################

function gql:op:query
{
    local -A _gql_doc
    gql:build-document _gql_doc query "$@"
    gql:format-document _gql_doc | gql:do - ${GQL[vars]:-}
}

##############################################################################

function gql:op:mutation
{
    local -A _gql_doc
    gql:build-document _gql_doc mutation "$@"
    gql:format-document _gql_doc | gql:do - ${GQL[vars]:-}
}

##############################################################################
##############################################################################

function gql:op:spool
{
    # (Very much a proof-of-concept)
    # Example:
    # gql -U 'https://rickandmortyapi.com/graphql' spool page=.characters.info.next characters.results page:Int characters page:=page { info { next } results { id name gender origin.name } } | jq -r '.[] | [ .id, .name, .gender, .origin.name ] | @tsv
    
    local spooler="$1"; shift || gql:required spooler 'spool config'
    local extract="$1"; shift || gql:required extract 'extraction JQ path'
    local -A _gql_doc
    gql:build-document _gql_doc query "$@"
    
    local cursorvar="${spooler%%=*}"
    local cursorpath="${spooler#*=}"
    local query="$(gql:format-document _gql_doc)"
    
    local cursor=null
    while [ "$cursor" ]
    do
        {
            read cursor
            cat
            
            if [ "$cursor" = null ]
            then
                cursor=
            fi
        } < <(
            gql:do "$query" ${GQL[vars]:-} "$cursorvar":"$cursor" | 
            jq "
                .${cursorpath#.},
                .${extract#.}
            "
        )            
    done        
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
        name="${arg%%:*}"
        if [ "$name" != "$arg" -a "${name#*=}" = "$name" ]
        then
            value="${arg#*:}"
            if [ ! "$value" ]
            then
                name=
            elif [ "${value#=}" != "$value" ]
            then
                value="\$${value#=}"
            fi
        else
            value="${arg#*=}"
            if [ "$value" = "$arg" ]
            then
                name=
            else
                name="${arg%%=*}"
                value="\"$value\""
            fi
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
        gql:agent:"${GQL[agent]:-curl}" |
        jq '
            if (has("errors"))
            then
                .errors[] | [ error(.message) ]
            else
                .data
            end
        ' 2> >( sed 's/jq: error.*): //' >&2; )
}
