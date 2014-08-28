var bodyParser = require('body-parser');
var request = require('request');
var express = require('express');
var app = express();
var cors = require('cors');
var nconf = require('nconf');

app.use(bodyParser.text({ type : 'application/xml' }));
app.use(cors());

var configFile = "config.json";

// Reads the config file, but overrides with any environment vars
nconf.file(configFile).env();

var v1ServiceUrl = nconf.get("v1ServiceUrl");
var v1Auth = "Basic " + (new Buffer(nconf.get("v1Auth")).toString('base64'));

function getUrl(url) {
    var fragment = url.substr(4, url.length - 4);
    return v1ServiceUrl + fragment;
}

function getHeaders(headers) {
    var result = {};
    for (h in headers) {
        if (h == 'host' || h == 'origin' || h == 'referer' || h == 'accept-encoding')
            continue;
        result[h] = headers[h];
    }
    result["authorization"] = v1Auth;
    return result;
}

function addHeaders(response, headers) {
    for (h in headers) {
        response.setHeader(h, headers[h]);
    }
}

function responseError(response, msg) {
    response.type('application/json; charset=utf-8');
    var error = { error: msg };
    response.end(JSON.stringify(error));
}

app.get('/pt/*', function (req, res, next) {
    try {
        var url = getUrl(req.url);
        var options = {
            url: url,
            method: 'GET',
            headers: getHeaders(req.headers)
        };
        
        request(options, function (error, response, body) {
            if (error) throw error.message;
            addHeaders(res, getHeaders(response.headers));
            res.end(body);
        });
    } catch (exception) {
        responseError(res, exception);
    }
});

app.post('/pt/*', function (req, res, next) {
    try {
        var options = {
            url: getUrl(req.url),
            method: 'POST',
            body: req.body,
            headers: getHeaders(req.headers)
        };
        
        request(options, function (error, response, body) {
            if (error) throw error.message;
            addHeaders(res, getHeaders(response.headers));
            res.status(200).send(body);
        });
    } catch (exception) {
        responseError(res, exception);
    }
    
});

var port = Number(process.env.PORT || 5000);

app.use(express.static(__dirname + '/client'));

app.listen(port, function () {
    console.log('CORS Proxy listening on port ' + port);
});