#!/bin/sh
DOC="ldoc"
LUAFILES=".."


### check Lua files
### https://github.com/mpeterv/luacheck
luacheck "${LUAFILES}"/*.lua

### API documentation
### https://stevedonovan.github.io/ldoc/
ldoc -d "${DOC}" -a -u "${LUAFILES}"
