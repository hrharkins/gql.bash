#!/usr/bin/env bash

[ "$GQL_CORE" ] || . "$(dirname "$(readlink -f "$0")")/gql.core.bash" &&
( return 0 2>/dev/null ) || gql:main "$@"
