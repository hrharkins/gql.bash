
##############################################################################
##############################################################################

function gql:format-document
{
    local -n _doc="$1"; shift || gql:required doc 'graphql document'
    local _indent='  '
    local _prefix=''
    local name="${_doc[:name]}"
    local -a vars=( ${_doc[:vars]:-} )

    echo -n "$_prefix${_doc[:op]}${name+ }$name"
    if [ ${#vars[@]} -gt 0 ]
    then
        local var comma=
        echo -n '('
        for var in "${vars[@]}"
        do
            echo -n "$comma\$${var#$}:${_doc[:vars:$var]}"
            comma=', '
        done
        echo ')'
    else
        echo
    fi
    
    _gql_format_selectors ''
}

##############################################################################

function _gql_format_node
{
    local path="$1"; shift || gql:required path 'document path'
    local name="${_doc[$path:name]:-}"
    
    [ "$name" ] || gql:warning "Path '$path' did not have a name"
    
    echo -n "$_prefix$name"
    _gql_format_args "$path:args"
    _prefix="$_prefix$_indent" _gql_format_directives "$path:directives"
    _gql_format_selectors "$path"
}    

##############################################################################

function _gql_format_args
{
    local path="$1"; shift || gql:required path 'document path'
    local argstr="${_doc[$path]:-}"
    if [ "$argstr" ]
    then
        local -a args=( $argstr )
        local arg comma=
        echo -n '('
        for arg in "${args[@]}"
        do
            echo -n "$comma$arg:${_doc[$path:$arg]:-}"
            comma=', '
        done
        echo ')'
    else
        echo
    fi        
}

##############################################################################

function _gql_format_directives
{
    local path="$1"; shift || gql:required path 'document path'
    local -i ndirectives="${_doc[$path]:-0}"
    local -i directiveidx=0
    
    while [ $directiveidx -lt $ndirectives ]
    do
        local directive="${_doc[$path/$directiveidx]}"
        echo -n "$_prefix@$directive"
        _gql_format_args "$path/$directiveidx:args"
        (( ++directiveidx ))
    done
}    

##############################################################################

function _gql_format_selectors
{
    local path="$1"; shift || gql:required path 'document path'
    local selectorstr="${_doc[$path:selectors]:-}"
    if [ "$selectorstr" ]
    then
        local -a selectors=( $selectorstr )
        local selector
        
        echo "$_prefix{"
        for selector in "${selectors[@]}"
        do
            _prefix="$_prefix$_indent" _gql_format_node "$path.$selector"
        done
        echo "$_prefix}"
    fi        
}

##############################################################################
##############################################################################