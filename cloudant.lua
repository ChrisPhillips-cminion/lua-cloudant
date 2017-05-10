
local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("json")
local mime = require("mime")
local URI = require("uri")

local Cloudant = { }

function dump(o)
  if type(o) == 'table' then
    local s = '{ '
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. dump(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end

function Cloudant:new(tbl) 
  tbl = tbl or {}
  setmetatable(tbl, self)

  self.__index = self

  assert(tbl.user)
  assert(tbl.password)

  self.baseuri = URI:new {
    scheme = 'https',
    host = assert(tbl.host),
    path = ''
  }
  print(self.baseuri);
  self.auth = "Basic " .. (mime.b64(string.format("%s:%s", tbl.user, tbl.password))) 

  return tbl
end

function Cloudant:database(name)
  self.dbname = assert(name)
end
function Cloudant:baseurl(baseuri)
  self.baseuri = assert(baseuri)
end

function Cloudant:url(endpoint)
  return self.baseuri:stringify(self.dbname .. '/' .. endpoint)
end

function Cloudant:instanceurl(endpoint)
  
  return self.baseuri:stringify(endpoint)
end

function Cloudant:request(method, url, params, data)
  local response_body = {}
  local req = { 
    url = url, 
    method = method, 
    sink = ltn12.sink.table(response_body), 
    headers = self.cookie and {['Cookie'] = self.cookie} or {['Authorization'] = self.auth}
  }

  if data then
    local jsonData = json.stringify(data)
    req.source = ltn12.source.string(jsonData)
    req.headers['Content-Type'] = 'application/json'
    req.headers['Content-Length'] = jsonData:len()
  end

  -- print(dump(req))

  local res, httpStatus, responseHeaders, status = http.request(req)
  return json.parse(table.concat(response_body))  
end

function Cloudant:authenticate()
  local response_body = {}
  local authdata = string.format('name=%s&password=%s', urlencode(self.user), urlencode(self.password))
  
  local req = { 
    url = self:instanceurl('_session'), 
    method = 'POST', 
    source = ltn12.source.string(authdata),
    sink = ltn12.sink.table(response_body),
    headers = {
      ['Content-Length'] = authdata:len(), 
      ['Content-Type']   = 'application/x-www-form-urlencoded'
    }
  }
  local res, httpStatus, responseHeaders, status = http.request(req)
  self.cookie = responseHeaders['set-cookie']
end

-- The CouchDB document API --

function Cloudant:bulkdocs(data, options)
  return self:request('POST', self:url('_bulk_docs'), options, {docs=data})
end

function Cloudant:read(docid, options)
  return self:request('GET', self:url(docid), options, nil)
end

function Cloudant:create(body, options) 
  local data = self:bulkdocs({body}, options)
  return data[1]
end

function Cloudant:update(docid, revid, body, options)
  body._id = docid
  body._rev = revid
  local data = self:bulkdocs({body}, options)
  return data[1]
end

function Cloudant:delete(docid, revid)
 local data = self:bulkdocs({{_id=docid, _rev=revid, _deleted=true}}, nil)
 return data[1]
end

function Cloudant:alldocs(options)
    return self:request('GET', self:url('_all_docs'), options, nil)
end

-- The CouchDB instance API --

function Cloudant:createdb()
  return self:request('PUT', self:instanceurl(self.dbname), nil, nil)
end

function Cloudant:dbinfo()
  return self:request('GET', self:instanceurl(self.dbname), nil, nil)
end

function Cloudant:deletedb()
  return self:request('DELETE', self:instanceurl(self.dbname), nil, nil)
end

function Cloudant:listdbs()
  return self:request('GET', self:instanceurl(''), nil, nil)
end

-- The CouchDB replication API --

function Cloudant:changes(options)
    return self:request('GET', self:url('_changes'), options, nil)
end

function urlencode(str)
   if (str) then
      str = string.gsub (str, "\n", "\r\n")
      str = string.gsub (str, "([^%w ])",
         function (c) return string.format ("%%%02X", string.byte(c)) end)
      str = string.gsub (str, " ", "+")
   end
   return str    
end

return Cloudant
