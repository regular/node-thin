#! /bin/bash
curl -v --raw -d @lib/client.gz -H "user-agent: git/1.7.9.5" -H "host: github.com" -H "accept-encoding: deflate, gzip" -H "content-type: application/x-git-upload-pack-request" -H "accept: application/x-git-upload-pack-result" -H "content-encoding: gzip" https://github.com/actano/docpad-plugin-lunr.git/git-upload-pack > bla

  