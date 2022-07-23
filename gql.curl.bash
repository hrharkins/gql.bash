
##############################################################################
##############################################################################

function gql:agent:curl
{
    local OPTIND OPTARG OPTARG
    local url="${GQL[url]:-}"
    
    while getopts 'u:' OPT
    do
        case "$OPT" in
        u) url="$url";;
        esac
    done
    shift $(( OPTIND - 1 ))
    
    [ "$url" ] || gql:required url 'GraphQL URL to access'
    
    curl -X POST --data-binary @- -H 'Content-Type: application/json' "$url"
}
