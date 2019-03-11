const functions = require('firebase-functions');
var rp = require('request-promise');

exports.getHTML = functions.https.onRequest((req, res)  => {
  const options = {
    method: 'POST',
    uri: 'https://my.gwu.edu/mod/pws/searchresults.cfm',
    form: {
      Submit:'Search',
      campus:'1',
      srchType:'All',
      term: req.body.term,
      courseNumSt: req.body.start,
      courseNumEn: req.body.end,
      pageNum: req.body.page
    }
  }
  rp(options).then(function(body) {
    res.send(body)
  })
});
