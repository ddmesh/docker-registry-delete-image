# docker-registry-delete-image
Tool to delete images/tags from docker registry. It uses curl and dialog (curses) to make it simpler to delete tags/images from
docker registry.

The script uses docker registry API version 2.

When using this script you do it on your own risk. I have tested it as best as I could. It comes with no waranty.

# Requirements:
		- linux
	 	- sudo jq dialog curl gawk

# Usage
<pre>
docker-registry-delete-image.sh Stephan Enderlein 2021, GNU General Public License v3.0 or later
Deletes image in docker registry (API version 2)

Usage:
 docker-registry-delete-image.sh [-r <registry-url>] [-p] [-i]
		-h		this help
		-r		url to docker registry
					Examples:
						http://localhost:5000
						https://user:password@myregistry.xy (note password might be stored
							in command shell history)
		-p		ask for password
		-i		ignores https certificate check
</pre>
