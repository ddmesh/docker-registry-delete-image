#!/bin/bash
# docker-registry-delete-image: menu driven command to delete images from docker registry
#
#
# Copyright (c) 2021, Stephan Enderlein. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software without
#    specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
# OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# See: https://opensource.org/licenses/BSD-3-Clause
#
#
# Requirements:
#		linux
#	 	jq dialog curl gawk
#


VERSION=2
COPYRIGHT="Stephan Enderlein 2021-present, BSD 3-Clause "New" or "Revised" License"

REQUIREMENTS="sudo apt install jq dialog"

API_VERSION="v2"
# - must be exactly this Accept header. If not used, requesting manifests for a tag will return
#   differnt data and different digests that can not be used for image deletion
HTTP_HEADER='Accept: application/vnd.docker.distribution.manifest.v2+json'

check_requirements()
{
  error=0
  for tool in jq dialog curl gawk
  do
    [ -z "$(which ${tool})" ] && echo "'${tool}' missing" && error=1
  done
  if [ "$error" = "1" ]; then
    echo "please install required tools:"
    echo "   ${REQUIREMENTS}"
    exit 1
  fi
}

# modifies global variable "REGISTRY",which holds url
modify_registry_url()
{
  user="$1"
  pass="$2"
  if [ -z "$REGISTRY" ]; then
    echo "Error: no registry url specified"
    exit 1
  fi

  # check if there are already credentials
  if [ "${REGISTRY}" != "${REGISTRY/@/}" ]; then
    echo "Error: username, password already in url"
    exit 1
  fi

  # insert AUTH into url
  #   check for "//"
  if [ "${REGISTRY}" != "${REGISTRY/\/\//}" ]; then
    proto="${REGISTRY%%//*}"
    host="${REGISTRY##*//}"
    REGISTRY="${proto}//${user}:${pass}@${host}"
  else
    REGISTRY="${user}:${pass}@${REGISTRY}"
  fi
}

get_catalog()
{
  registry="$1"
  curl --raw ${CURL_INSECURE} --silent -H "${HTTP_HEADER}" -X GET "${registry}/${API_VERSION}/_catalog"
}

# gets repositories as string for curses menu
extract_repositories()
{
  json="$1"

  # get repositories
  entries=""
  for repo in $(echo $json | jq --raw-output '.repositories[]')
  do
    test "${repo}" = "null" && break
    entries="${entries} '${repo}' ''"
  done
  echo "${entries}"
}

get_tags()
{
  registry="$1"
  repo="$2"
  curl --raw ${CURL_INSECURE} --silent -H "${HTTP_HEADER}" -X GET "${registry}/${API_VERSION}/${repo}/tags/list"
}

extract_tags()
{
  json="$1"

  json_tags=$(echo $json | jq --raw-output '.tags')
  test "${json_tags}" = "null" && return

  # get repositories
  entries=""
  for tag in $(echo $json_tags | jq --raw-output '.[]')
  do
    entries="${entries} '${tag}' ''"
  done
  echo "${entries}"
}

get_digest()
{
  registry="$1"
  repo="$2"
  tag="$3"
  # get digest and remove '\r\n' at the end of it (else url using digest will fail)
  curl --raw ${CURL_INSECURE} --silent --head -H "${HTTP_HEADER}" -X GET "${registry}/${API_VERSION}/${repo}/manifests/${tag}" \
        | awk 'BEGIN{RS="\r\n"; IGNORECASE = 1} /^Docker-Content-Digest:/{ print $2 }'
}

delete_image()
{
  registry="$1"
  repo="$2"
  digest="$3"

  curl --raw ${CURL_INSECURE} --head -H "${HTTP_HEADER}" -X DELETE ${registry}/${API_VERSION}/${repo}/manifests/${digest}
}

usage()
{
cat <<EOM
$(basename $0) v${VERSION}, ${COPYRIGHT}
Interactively deletes docker images from docker registry (using docker registry API version 2).

Usage:
 $(basename $0) [-r <registry-url>] [-p] [-i]
    -h  this help
    -r  url to docker registry
          Examples:
            http://localhost:5000
            https://user:password@myregistry.xy (note password might be stored
              in command shell history)
    -p  ask for password
    -i  ignores https certificate check

EOM
}

# pre checks
check_requirements


# process parameters; all must start with "-"
ARG="$1"
if [ -z "$ARG" -o "${ARG:0:1}" != "-" ]; then
  usage
  exit 1
fi

REGISTRY=""
AUTH=""

while getopts ":hr:pi" opt; do

  case "${opt}" in
    h)
        usage
        exit 1
        ;;
    r)
      REGISTRY="${OPTARG}"
      ;;
    p)
      read -p "username:" AUTH_USER
      read -s -p "password:" AUTH_PASSWORD
      ;;
    i)
      CURL_INSECURE="--insecure"
      ;;
    '?')
      echo "Invalid Option: -$OPTARG" 1>&2
      exit 1
      ;;
    : )
      echo "Invalid Option: -$OPTARG requires an argument" 1>&2
      exit 1
  esac
done

# insert AUTH into url
if [ -n "${AUTH_USER}" -a -n "${AUTH_PASSWORD}" ]; then
  modify_registry_url ${AUTH_USER} ${AUTH_PASSWORD}
fi

# get repositories
json_repos=$(get_catalog ${REGISTRY})

if [ -z "$json_repos" ]; then
  echo "Error: accessing registry. check https certificates if used."
  exit 1
fi

repositories=$(extract_repositories "${json_repos}")
if [ -z "$repositories" ]; then
  echo "Error: no repositories found"
  echo "$json_repos"
  exit 1
fi


# menu: repository
while true
do

  repo="$(eval dialog --clear --stdout --cancel-label "Exit" --title \'${REGISTRY}\' --menu \'Docker Repositories\' 0 0 0 ${repositories})"
  [ -z "${repo}" ] && clear && exit 1

  # menu: tags
  while true
  do
    # display tags
    json_tags=$(get_tags ${REGISTRY} ${repo})
    tags=$(extract_tags "${json_tags}")
    if [ -z "$tags" ]; then
      dialog --clear --title "${REGISTRY}" --msgbox "Repository '${repo}' has no tags" 0 0
      break
    fi

    tag="$(eval dialog --clear --stdout --cancel-label "Back" --title \"${REGISTRY}\" --menu \'${repo} tags:\' 0 0 0 ${tags})"
    [ -z "${tag}" ] && break

    # get digest for selected target
    digest="$(get_digest ${REGISTRY} ${repo} ${tag})"
    if [ -z "$digest" ]; then
      dialog --clear --title "${REGISTRY}" --msgbox "Error getting digest for: ${repo}/${tag}" 0 0
      continue
    fi

    # delete ?
    MSG="Are you sure to delete\n'${tag}'?\n\nNote: ALL tags that have same digest are deleted also !!!\n\n${digest}"
    if dialog --clear --stdout --default-button no --yes-label "DELETE" --title "${REGISTRY}" --yesno "${MSG}" 0 0; then

      delete_image "${REGISTRY}" "${repo}" "${digest}"

      MSG="All tags with digest:\n"
      MSG="${MSG}   ${digest}\n"
      MSG="${MSG}should be deleted. If the image is still present, the registry\n"
      MSG="${MSG}was configured read-only. Start registry with option:\n"
      MSG="${MSG}									-e REGISTRY_STORAGE_DELETE_ENABLED=true\n\n"
      MSG="${MSG}Docker registry runs a garbage-collector\n"
      MSG="${MSG}to finally remove unused data.\n"
      MSG="${MSG}You may call the garbage collector yourself:\n\n"
      MSG="${MSG}* docker exec -it registry /bin/registry garbage-collect \\ \n"
      MSG="${MSG}      [--dry-run]    /etc/docker/registry/config.yml -m\n\n"
      MSG="${MSG}You also might restart the registry to clear any cache before\n"
      MSG="${MSG}uploading same images again:\n\n"
      MSG="${MSG}* docker restart registry"
      dialog --clear --title "${REGISTRY}" --msgbox "${MSG}" 0 0
    else
      dialog --clear --title "${REGISTRY}" --msgbox "deletion canceled" 0 0
    fi
  done # menu: tags

done # menu: repository
