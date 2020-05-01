#!/bin/bash

function get_cpus_allowed() {
    echo "$(grep Cpus_allowed_list /proc/self/status | cut -f 2)"
}

function expand_number_list() {
    # expand a list of numbers to no longer include a range
    # ie. "1-3,5" becomes "1,2,3,5"
    local range=${1}
    local list=""
    local items=""
    local item=""
    for items in $(echo "${range}" | sed -e "s/,/ /g"); do
	if echo ${items} | grep -q -- "-"; then
	    items=$(echo "${items}" | sed -e "s/-/ /")
	    items=$(seq ${items})
	fi
	for item in ${items}; do
	    list="${list},$item"
	done
    done
    list=$(echo "${list}" | sed -e "s/^,//")
    echo "${list}"
}

function separate_comma_list() {
    echo "${1}" | sed -e "s/,/ /g"
}
