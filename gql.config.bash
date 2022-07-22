
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
