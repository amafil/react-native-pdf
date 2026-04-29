cd /Users/filippo/Documents/react-native-pdf
npm version patch
npm pack --dry-run
npm publish --access public
git push --follow-tags

!IMPORTANT: check the access token expiration on npmjs.com before running the above commands, otherwise the publish will fail.