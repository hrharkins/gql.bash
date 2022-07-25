
##############################################################################
##############################################################################

function gql:merge-config
{
    local -n dest="$1"; shift || gql:required dest 'merge destination variable'
    local srcvar var
    for srcvar in "$@"
    do
        local -n src="$srcvar"
        for var in "${!src[@]}"
        do
            dest["$var"]="${src["$var"]}"
        done
    done
}

##############################################################################
##############################################################################

function gql:load-config
{
    local config="$1"; shift || gql:required dest 'merge destination variable'
    if [ -r "$config" ]
    then
        . "$config"
    fi
}

##############################################################################
##############################################################################

function gql:get-config
{
    local -n dest="$1"; shift || gql:required dest 'destination variable'
    local var="${1:-${!dest}}"
    local profile="${GQL[profile]:-}"
    dest="${GQL[$var]:-${GQL[profile:$profile:$var]:-:-${2:-}}}"
}
