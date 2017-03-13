(function($) {
  if (typeof($) === 'undefined') {
    var scriptPath = "fhem/pgm2/jquery.min.js";
    var xhrObj = new XMLHttpRequest();
    scriptPath = addcsrf(scriptPath);
    xhrObj.open('GET', scriptPath, false);
    xhrObj.send(null);
    var newscript = document.createElement('script');
    newscript.type = 'text/javascript';
    newscript.async = false;
    newscript.text = xhrObj.responseText;
    xhrObj.abort();
    (document.head||document.getElementsByTagName('head')[0]).appendChild(newscript);
  }
  // window.fh_jQuery = $.noConflict(true);
})(jQuery);

(function($) {
  if (typeof($.ui) === 'undefined') {
    var scriptPath = "fhem/pgm2/jquery-ui.min.js";
    var xhrObj = new XMLHttpRequest();
    scriptPath = addcsrf(scriptPath);
    xhrObj.open('GET', scriptPath, false);
    xhrObj.send(null);
    var newscript = document.createElement('script');
    newscript.type = 'text/javascript';
    newscript.async = false;
    newscript.text = xhrObj.responseText;
    xhrObj.abort();
    (document.head||document.getElementsByTagName('head')[0]).appendChild(newscript);
    var cssFile = "fhem/pgm2/jquery-ui.min.css";
    var fileref=document.createElement("link");
    fileref.setAttribute("rel", "stylesheet");
    fileref.setAttribute("type", "text/css");
    fileref.setAttribute("href", cssFile);
    (document.head||document.getElementsByTagName('head')[0]).appendChild(fileref);
  }
})(jQuery);

function sveReadGADList(device) {
  console.log('read list');
  var token = $("body").attr('fwcsrf') ? '&fwcsrf=' + $("body").attr('fwcsrf') : '';
  var url = $(location).attr('pathname');
  var transfer = {};
  transfer.cmd = 'gadList';
  var dataString = 'dev.' + device + '=' + device + '&cmd.' + device + '=get&arg.' + device + '=webif-data&val.' + device + '=' + JSON.stringify(transfer) + '&XHR=1' + token;
  $.ajax({
    type: "POST",
    url: url,
    data: dataString,
    cache: false,
    success: function (gadList) {
      sveRefreshGADList(device, gadList);
    }
  });
}

function sveRefreshGADList(device, gadList) {
  console.log('refresh list');
  var gad = $.parseJSON(gadList);
  var insert = [];
  var keys = Object.keys(gad);
  var len = keys.length;
  keys.sort();
  insert.push('<input id="filterTable_input">');
  insert.push('<table id="gadlisttable" style="width:636px">');
  insert.push('<thead><tr><th></th><th>gad</th><th>device</th><th>r</th><th>w</th></tr></thead><tbody id="gadlisttablebody">');
  //$.each(gad, function(i, item) {
  //  insert.push('<tr id=' + i + ' style="cursor:pointer"><td><a>' + i + '</a></td><td>nnn</td></tr>');
  //});
  for (var i = 0; i < len; i++)
  {
    var key = keys[i];
    insert.push('<tr id=' + key + ' style="cursor:pointer"><td>' + 
      ((gad[key]['monitor'] == 1)?'<img height="12" src="fhem/images/default/desktop.svg">':'') + '</td><td><a>' + 
      key + '</a></td><td>' +       
      ((typeof gad[key]['device'] == 'string')?gad[key]['device']:'') + '</td><td>' +
      ((gad[key]['read'] == 1)?'<img height="12" src="fhem/images/default/arrow-down.svg">':'') + '</td><td>' + 
      ((gad[key]['write'] == 1)?'<img height="12" src="fhem/images/default/arrow-up.svg">':'') + '</td></tr>');
    console.log(gad[key]['device']);
  }
  
  insert.push('</tbody></table>');
  $('#gadlist').html(insert.join(''));
  $('#gadlisttable tr').click(function () {
    sveLoadGADitem(device, $(this).attr('id'));
  });
  $("#filterTable_input").keyup(function () {
	    //split the current value of searchInput
	    var data = this.value.split(" ");
	    //create a jquery object of the rows
	    var jo = $("#gadlisttablebody").find("tr");
	    if (this.value == "") {
	        jo.show();
	        return;
	    }
	    //hide all the rows
	    jo.hide();
	    //Recusively filter the jquery object to get results.
	    jo.filter(function (i, v) {
	        var $t = $(this);
	        for (var d = 0; d < data.length; ++d) {
	            if ($t.is(":contains('" + data[d] + "')")) {
	                return true;
	            }
	        }
	        return false;
	    })
	    //show the rows that match.
	    .show();
	}).focus(function () {
	    this.value = "";
	    $(this).css({
	        "color": "black"
	    });
	    $(this).unbind('focus');
	}).css({
	    "color": "#C0C0C0"
	});
}

function sveLoadGADitem(device, gadName) {
  console.log('load item');
  var url = $(location).attr('pathname');
  var transfer = {};
  transfer.cmd = 'gadItem';
  transfer.item = gadName;
  var dataString ='dev.' + device + '=' + device + '&cmd.' + device + '=get&arg.' + device + '=webif-data&val.' + device + '=' + JSON.stringify(transfer) + '&XHR=1';
  dataString = addcsrf(dataString);
  $.ajax({
      type: "POST",
      url: url,
      data: dataString,
      cache: false,
      success: function (gadItem) {
        sveShowGADEditor(device, gadName, gadItem);
      }
    });
}

function sveShowGADEditor(device, gadName, gadItem) {
  console.log('show editor');
  var gad = $.parseJSON(gadItem);
  var mode = gad.editor;
  console.log(gad);
  console.log(mode);
  switch (mode) {
    case 'item':
      $('#gadeditcontainer').finish();
      sveGADEditorItem(device, gadName, gad);
      break;
    default:
      sveGADEditorTypeSelect(device, gadName, gad);
      break;
  }
  return;
}

function sveGADEditorItem(device, gadName, gad) {
  console.log('edtor item');
  console.log(gadName);
  $('#gadeditor').replaceWith($('<table/>', {id: 'gadeditor'}));
  //$('#gadeditor').width('100%');
  $('#gadeditor').append('<tr><th colspan="2">' + gadName + '</th></tr>');

  sveGADEdtorAddTypeSelect(device, gadName, gad);
  $('#gadEditTypeSelect').change(function() {
    var transfer = {
      cmd: 'gadModeSelect',
      item: gadName,
      editor: $(this).val()
    };
    sveGADEditorSave(device, gadName, transfer, function() {sveLoadGADitem(device, gadName)});
  });
  
  $('#gadeditor').append('<tr><td>' + 'device' + '</td><td align="right"><input id="gadEditDevice" type="text" size="55" value="' + gad.device +'"/></td></tr>');
  $('#gadeditor').append('<tr><td>' + 'reading' + '</td><td align="right"><input id="gadEditReading" type="text" size="55" value="' + gad.reading +'"/></td></tr>');
  $('#gadeditor').append('<tr><td>' + 'converter' + '</td><td align="right"><input id="gadEditConverter" type="text" size="55" value="' + gad.converter +'"/></td></tr>');
  $('#gadeditor').append('<tr><td>' + 'cmd set' + '</td><td align="right"><input id="gadEditSet" type="text" size="55" value="' + gad.set +'"/></td></tr>');
  $('#gadeditor').append('<tr class="permission"><td>&nbsp;</td><td>&nbsp;</td></tr>');
  $('#gadeditor').append('<tr class="permission"><th colspan="2">permission for ' + device + '</th></tr>');
  $('#gadeditor').append('<tr class="permission"><td ><input type="checkbox" id="gadEditRead" ' + gad.read + '>read</td><td align="right"> PIN GAD: <input type="text" size="45" id="gadEditReadConverter" value="kommt später"></td>');
  $('#gadeditor').append('<tr class="permission"><td ><input type="checkbox" id="gadEditWrite" ' + gad.write + '>write</td><td align="right"> PIN GAD: <input type="text" size="45" id="gadEditWriteConverter" value="auch ;-)"></td>');
  
  if (gad.whitelist === 'false') $('.permission').hide();

  //preload autocomplete device
  $('#gadEditDevice').autocomplete({source: gad.deviceList, minLength: 0});
  $('#gadEditConverter').autocomplete({source: gad.converterList, minLength: 0});
  //dynamic loader for readings and sets
  $('#gadEditDevice').blur(function(){
    if ($('#gadEditDevice').val() === '') return;
    var transfer = {
      cmd: 'gadItemDeviceChanged',
      item: gadName,
      device: $('#gadEditDevice').val()
    };
    var url = $(location).attr('pathname');
    var dataString ='dev.' + device + '=' + device + '&cmd.' + device + '=get&arg.' + device + '=webif-data&val.' + device + '=' + JSON.stringify(transfer) + '&XHR=1';
    dataString = addcsrf(dataString);
    $.ajax({
      type: "POST",
      url: url,
      data: dataString,
      cache: false,
      success: function(r) {
        console.log ("result " + r);
        var result = $.parseJSON(r);
        if (result.result == 'error')  {
          $('#gadEditReading').autocomplete({source: [], minLength: 0});
          $('#gadEditSet').autocomplete({source: [], minLength: 0});
          return;
        }
        $('#gadEditReading').autocomplete({source: result.readings, minLength: 0});
        $('#gadEditSet').autocomplete({source: result.sets, minLength: 0});
      }
    });
  });


  //$('#gadEditReading').autocomplete({source: gad.deviceList});
  // preload readings and set
  $('#gadEditDevice').trigger('blur');
  //sveGADEdtorAddPermissionSelect(device, gadName, gad);
  $('#gadeditor').append('<tr><td>&nbsp;</td><td>&nbsp;</td></tr>');
  $('#gadeditor').append('<button id="gadEditDelete" type="button">delete</button>');
  $('#gadeditor').append('<button id="gadEditCancel" type="button">cancel</button>');
  $('#gadeditor').append('<button id="gadEditSave" type="button">save</button>');

  $('#gadEditDelete').click(function() {
    sveGADEditorDelete(device, gadName, gad);
  });

  $('#gadEditSave').click(function() {
    var transfer = {
      cmd: 'gadItemSave',
      item: gadName,
      editor: $('#gadEditTypeSelect').val(),
      config: {
        type: 'item',
        device: $('#gadEditDevice').val(),
        reading: $('#gadEditReading').val(),
        converter: $('#gadEditConverter').val(),
        set: $('#gadEditSet').val(),
        read: $('#gadEditRead').is(':checked')?'1':'0',
        write: $('#gadEditWrite').is(':checked')?'1':'0',
        readPinGAD: $('#gadEditReadPinGAD').val(),
        writePinGAD: $('#gadEditWritePinGAD').val()
      },
      access: $('#gadEditPermissionSelect').val()
    };
    sveGADEditorSave(device, gadName, transfer, function(){
      $('#' + gadName + ' td:eq(3)').html($('#gadEditRead').is(':checked')?'<img height="12" src="fhem/images/default/arrow-down.svg">':'');
      $('#' + gadName + ' td:eq(4)').html($('#gadEditWrite').is(':checked')?'<img height="12" src="fhem/images/default/arrow-up.svg">':'');
      $('#gadeditor').replaceWith($('<p>', {id: 'gadeditor', text: 'save setting: ' + gadName + ' ...', style: 'color: green'}));
      $('#gadeditcontainer').delay(1500).fadeOut();
    });
  });

  $('#gadEditCancel').click(function() {
    $('#gadeditor').replaceWith($('<p>', {id: 'gadeditor', text: 'edit cancelled ...', style: 'color: green'}));
    $('#gadeditcontainer').delay(1500).fadeOut();
  });
  $('#gadeditcontainer').show();
}

function sveGADEditorTypeSelect(device, gadName, gad) {
  console.log('type select');
  console.log(gadName);
  $('#gadeditor').replaceWith($('<table/>', {id: 'gadeditor'}));
  $('#gadeditor').append('<tr><td>' + 'GAD' + '</td><td>' + gadName +'</td></tr>');

  sveGADEdtorAddTypeSelect(device, gadName, gad);
  $('#gadEditTypeSelect').change(function() {
    var transfer = {
      cmd: 'gadModeSelect',
      item: gadName,
      editor: $(this).val()
    };
    sveGADEditorSave(device, gadName, transfer, function() {sveLoadGADitem(device, gadName);});
  });

  $('#gadeditcontainer').show();
}

function sveGADEditorDelete(device, gadName, gad) {
  console.log('delete');
  console.log(gadName);
  $('#gadeditor').replaceWith($('<p>', {id: 'gadeditor', text: 'confirm delete: ' + gadName + ' !', style: 'color: red'}));
  $('#gadeditor').append('<p>');
  $('#gadeditor').append('<button id="gadEditCancelConfirm" type="button">cancel</button>');
  $('#gadEditCancelConfirm').click(function() {
    $('#gadeditor').replaceWith($('<p>', {id: 'gadeditor', text: 'delete cancelled ...', style: 'color: green'}));
    $('#gadeditcontainer').delay(1500).fadeOut();
  });
  $('#gadeditor').append('<button id="gadEditDeleteConfirm" type="button">delete</button>');
  $('#gadEditDeleteConfirm').click(function() {
    $('#gadeditor').replaceWith($('<p>', {id: 'gadeditor', text: gadName + ' vanished ... (bye)', style: 'color: red'}));
    $('#gadeditcontainer').delay(1500).fadeOut();
    var transfer = {
      cmd: 'gadItemDelete',
      item: gadName
    };
    var success = function() {
      sveReadGADList(device);      
    };
    sveGADEditorSave(device, gadName, transfer, success);
  });

  //$('#gadeditcontainer').show();
}

function sveGADEdtorAddTypeSelect(device, gadName, gad) {
  console.log('add type select');
  console.log(gad);
  $('#gadeditor').append('<tr><td>' + 'mode' + '</td><td><select id="gadEditTypeSelect"/></td></tr>');
  $('<option/>').val('item').text('item').appendTo('#gadEditTypeSelect');
  $('<option/>').val('plot').text('plot').appendTo('#gadEditTypeSelect');
  $('#gadEditTypeSelect').val(gad.editor);
}

function sveGADEditorSave(device, gadName, transfer, success, error) {
  console.log('gad save');
  var url = $(location).attr('pathname');
  var dataString ='dev.' + device + '=' + device + '&cmd.' + device + '=get&arg.' + device + '=webif-data&val.' + device + '=' + JSON.stringify(transfer) + '&XHR=1';
  dataString = addcsrf(dataString);
  $.ajax({
    type: "POST",
    url: url,
    data: dataString,
    cache: false,
    success: success
  });
}

function sveGADEdtorAddPermissionSelect() {
  console.log('add permission');
  $('#gadeditor').append('<tr><td>' + 'access' + '<unknown device/td><td><select id="gadEditPermissionSelect"/></td></tr>');
  $('<option/>').val('none').text('none').appendTo('#gadEditPermissionSelect');
  $('<option/>').val('r').text('read').appendTo('#gadEditPermissionSelect');
  $('<option/>').val('w').text('write').appendTo('#gadEditPermissionSelect');
  $('<option/>').val('rw').text('read/write').appendTo('#gadEditPermissionSelect');
  $('<option/>').val('pin').text('pin (special)').appendTo('#gadEditPermissionSelect');
  $('#gadEditPermissionSelect').val('pin');
}

