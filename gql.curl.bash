
##############################################################################
##############################################################################

function gql:agent:curl
{
    local OPTIND OPTARG OPTARG
    #local url="${GQL[url]:-${GQL[profile:${GQL[profile]:-}:url]:-}}"
    local url
    gql:get-config url
    
    while getopts 'u:' OPT
    do
        case "$OPT" in
        u) url="$url";;
        esac
    done
    shift $(( OPTIND - 1 ))
    
    [ "$url" ] || gql:required url 'GraphQL URL to access'
    
    curl -s -X POST --data-binary @- -H 'Content-Type: application/json' "$url"
}
