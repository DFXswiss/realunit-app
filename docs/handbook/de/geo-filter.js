/**
 * Live RealUnit share-token geo-filter table.
 *
 * Source of truth is GET /v1/country. Rows are never copied into this repo.
 * Country labels are German and English via Intl.DisplayNames (ISO 3166-1),
 * not API foreignName (often native script).
 */
(function () {
  var URLS = ['/v1/country', 'https://api.dfx.swiss/v1/country'];
  var COLUMNS = [
    { key: 'symbol', label: 'ISO' },
    { key: 'nameDe', label: 'Land (DE)' },
    { key: 'nameEn', label: 'Country (EN)' },
    { key: 'residence', label: 'Wohnsitz' },
    { key: 'nationality', label: 'Nationalität' },
    { key: 'residenceExisting', label: 'Wohnsitz Bestand' },
    { key: 'nationalityExisting', label: 'Nationalität Bestand' },
    { key: 'ipEnable', label: 'IP neu' },
    { key: 'ipExisting', label: 'IP Bestand' },
    { key: 'taxEnable', label: 'Steuer neu' },
    { key: 'taxExisting', label: 'Steuer Bestand' },
  ];

  var displayDe;
  var displayEn;
  try {
    displayDe = new Intl.DisplayNames(['de'], { type: 'region', fallback: 'none' });
    displayEn = new Intl.DisplayNames(['en'], { type: 'region', fallback: 'none' });
  } catch (e) {
    try {
      displayDe = new Intl.DisplayNames(['de'], { type: 'region' });
      displayEn = new Intl.DisplayNames(['en'], { type: 'region' });
    } catch (e2) {
      displayDe = null;
      displayEn = null;
    }
  }

  function $(id) {
    return document.getElementById(id);
  }

  function regionName(display, symbol, fallback) {
    if (display && symbol) {
      try {
        var label = display.of(symbol);
        if (label && String(label).toUpperCase() !== String(symbol).toUpperCase()) {
          return label;
        }
      } catch (e) {}
    }
    return fallback || symbol || '';
  }

  function cell(value) {
    if (value === true) return 'ja';
    if (value === false) return 'nein';
    if (value == null || value === '') return '—';
    return String(value);
  }

  function tone(field, value) {
    if (value == null || value === '') return 'muted';
    if (field === 'residence') {
      if (value === 'Allowed') return 'ok';
      if (value === 'Sanction') return 'bad';
      if (value === 'Restricted') return 'warn';
      return 'muted';
    }
    if (field === 'nationality') {
      if (value === 'Ok') return 'ok';
      if (value === 'Blocked') return 'bad';
      if (value === 'Exception') return 'warn';
      return 'muted';
    }
    if (value === true) return 'ok';
    if (value === false) return 'bad';
    return 'muted';
  }

  function rowView(country) {
    var geo = country.realunit || {};
    var english = country.name || country.symbol;
    return {
      symbol: country.symbol,
      nameDe: regionName(displayDe, country.symbol, english),
      nameEn: regionName(displayEn, country.symbol, english),
      residence: geo.residence,
      nationality: geo.nationality,
      residenceExisting: geo.residenceExisting,
      nationalityExisting: geo.nationalityExisting,
      ipEnable: geo.ipEnable,
      ipExisting: geo.ipExisting,
      taxEnable: geo.taxEnable,
      taxExisting: geo.taxExisting,
    };
  }

  function load(urls) {
    var url = urls[0];
    return fetch(url, { credentials: 'same-origin' }).then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json().then(function (body) {
        if (!Array.isArray(body)) throw new Error('unexpected payload');
        return { body: body, url: url };
      });
    }).catch(function (err) {
      if (urls.length > 1) return load(urls.slice(1));
      throw err;
    });
  }

  function filteredRows(state) {
    var q = ($('geo-filter-search') || {}).value || '';
    q = q.trim().toLowerCase();
    var residence = ($('geo-filter-residence') || {}).value || '';
    var nationality = ($('geo-filter-nationality') || {}).value || '';
    return state.rows.filter(function (row) {
      if (
        q &&
        (row.symbol || '').toLowerCase().indexOf(q) < 0 &&
        (row.nameDe || '').toLowerCase().indexOf(q) < 0 &&
        (row.nameEn || '').toLowerCase().indexOf(q) < 0
      ) {
        return false;
      }
      if (residence && row.residence !== residence) return false;
      if (nationality && row.nationality !== nationality) return false;
      return true;
    });
  }

  function stamp() {
    var d = new Date();
    var p = function (n) {
      return n < 10 ? '0' + n : String(n);
    };
    return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
  }

  function fileBase() {
    return 'realunit-geo-filter-' + stamp();
  }

  function saveBlob(blob, filename) {
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () {
      URL.revokeObjectURL(url);
    }, 1000);
  }

  function xmlEscape(value) {
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function csvField(value) {
    var s = cell(value);
    if (/[;"\n\r]/.test(s)) return '"' + s.replace(/"/g, '""') + '"';
    return s;
  }

  function downloadCsv(rows) {
    var lines = [COLUMNS.map(function (c) { return csvField(c.label); }).join(';')];
    rows.forEach(function (row) {
      lines.push(COLUMNS.map(function (c) { return csvField(row[c.key]); }).join(';'));
    });
    var blob = new Blob(['\uFEFF' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
    saveBlob(blob, fileBase() + '.csv');
  }

  function downloadExcel(rows) {
    var xml = '<?xml version="1.0" encoding="UTF-8"?>\r\n';
    xml += '<?mso-application progid="Excel.Sheet"?>\r\n';
    xml += '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" ';
    xml += 'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">\r\n';
    xml += '<Worksheet ss:Name="Geo-Filter"><Table>\r\n';
    xml += '<Row>' + COLUMNS.map(function (c) {
      return '<Cell><Data ss:Type="String">' + xmlEscape(c.label) + '</Data></Cell>';
    }).join('') + '</Row>\r\n';
    rows.forEach(function (row) {
      xml += '<Row>' + COLUMNS.map(function (c) {
        return '<Cell><Data ss:Type="String">' + xmlEscape(cell(row[c.key])) + '</Data></Cell>';
      }).join('') + '</Row>\r\n';
    });
    xml += '</Table></Worksheet></Workbook>';
    var blob = new Blob([xml], { type: 'application/vnd.ms-excel' });
    saveBlob(blob, fileBase() + '.xls');
  }

  var WINANSI = {
    0x20ac: 128,
    0x201a: 130,
    0x0192: 131,
    0x201e: 132,
    0x2026: 133,
    0x2020: 134,
    0x2021: 135,
    0x02c6: 136,
    0x2030: 137,
    0x0160: 138,
    0x2039: 139,
    0x0152: 140,
    0x017d: 142,
    0x2018: 145,
    0x2019: 146,
    0x201c: 147,
    0x201d: 148,
    0x2022: 149,
    0x2013: 150,
    0x2014: 151,
    0x02dc: 152,
    0x2122: 153,
    0x0161: 154,
    0x203a: 155,
    0x0153: 156,
    0x017e: 158,
    0x0178: 159,
  };

  function pdfEscape(text) {
    var s = '';
    var raw = String(text);
    for (var i = 0; i < raw.length; i++) {
      var code = raw.charCodeAt(i);
      if (WINANSI[code] != null) code = WINANSI[code];
      if (code === 92) s += '\\\\';
      else if (code === 40) s += '\\(';
      else if (code === 41) s += '\\)';
      else if (code === 13 || code === 10) s += ' ';
      else if (code >= 32 && code < 128) s += String.fromCharCode(code);
      else if (code >= 128 && code <= 255) s += '\\' + ('00' + code.toString(8)).slice(-3);
      else s += '?';
    }
    return s;
  }

  function downloadPdf(rows) {
    var pageW = 842;
    var pageH = 595;
    var margin = 32;
    var fontSize = 8;
    var lineH = 11;
    var headerH = 36;
    var usable = pageH - margin * 2 - headerH;
    var rowsPerPage = Math.max(1, Math.floor(usable / lineH) - 1);
    var pages = [];
    for (var i = 0; i < rows.length || (rows.length === 0 && pages.length === 0); i += rowsPerPage) {
      pages.push(rows.slice(i, i + rowsPerPage));
      if (rows.length === 0) break;
    }
    var colX = [margin, 62, 168, 274, 348, 422, 496, 546, 596, 646, 700];

    function pageStream(pageRows, pageIndex, pageCount) {
      var y = pageH - margin - 14;
      var out = 'BT\n/F1 11 Tf\n';
      out += margin + ' ' + y + ' Td\n(' + pdfEscape('RealUnit Aktientoken — Geo-Filter') + ') Tj\n';
      out += '/F1 8 Tf\n0 -12 Td\n(' + pdfEscape(fileBase() + '  ·  Seite ' + (pageIndex + 1) + '/' + pageCount) + ') Tj\n';
      y -= headerH;
      out += '/F1 8 Tf\n';
      COLUMNS.forEach(function (col, idx) {
        out += '1 0 0 1 ' + colX[idx] + ' ' + y + ' Tm\n(' + pdfEscape(col.label) + ') Tj\n';
      });
      y -= lineH;
      pageRows.forEach(function (row) {
        COLUMNS.forEach(function (col, idx) {
          var value = cell(row[col.key]);
          if (value.length > 22 && (col.key === 'nameDe' || col.key === 'nameEn')) value = value.slice(0, 21) + '...';
          out += '1 0 0 1 ' + colX[idx] + ' ' + y + ' Tm\n(' + pdfEscape(value) + ') Tj\n';
        });
        y -= lineH;
      });
      out += 'ET\n';
      return out;
    }

    var objects = [];
    objects.push('<< /Type /Catalog /Pages 2 0 R >>');
    var pageIds = [];
    var contentIds = [];
    var fontId;
    var startId = 3;
    for (var p = 0; p < pages.length; p++) {
      pageIds.push(startId + p);
      contentIds.push(startId + pages.length + p);
    }
    fontId = startId + pages.length * 2;
    var kids = pageIds.map(function (id) { return id + ' 0 R'; }).join(' ');
    objects.push('<< /Type /Pages /Kids [' + kids + '] /Count ' + pages.length + ' >>');

    var contents = [];
    pages.forEach(function (pageRows, idx) {
      objects.push(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' +
          pageW +
          ' ' +
          pageH +
          '] /Contents ' +
          contentIds[idx] +
          ' 0 R /Resources << /Font << /F1 ' +
          fontId +
          ' 0 R >> >> >>'
      );
      contents[idx] = pageStream(pageRows, idx, pages.length);
    });
    contents.forEach(function (stream) {
      objects.push('<< /Length ' + stream.length + ' >>\nstream\n' + stream + 'endstream');
    });
    objects.push('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');

    var xref = [0];
    var pdf = '%PDF-1.4\n';
    objects.forEach(function (body, idx) {
      xref.push(pdf.length);
      pdf += idx + 1 + ' 0 obj\n' + body + '\nendobj\n';
    });
    var xrefPos = pdf.length;
    pdf += 'xref\n0 ' + (objects.length + 1) + '\n';
    pdf += '0000000000 65535 f \n';
    xref.slice(1).forEach(function (offset) {
      var n = String(offset);
      pdf += ('0000000000' + n).slice(-10) + ' 00000 n \n';
    });
    pdf += 'trailer\n<< /Size ' + (objects.length + 1) + ' /Root 1 0 R >>\nstartxref\n' + xrefPos + '\n%%EOF';
    saveBlob(new Blob([pdf], { type: 'application/pdf' }), fileBase() + '.pdf');
  }

  function render(state) {
    var tbody = $('geo-filter-body');
    var status = $('geo-filter-status');
    var missing = $('geo-filter-missing');
    if (!tbody) return;

    var rows = filteredRows(state);
    tbody.textContent = '';
    rows.forEach(function (row) {
      var tr = document.createElement('tr');
      COLUMNS.forEach(function (col) {
        var td = document.createElement('td');
        td.textContent = cell(row[col.key]);
        td.className = 'geo-tone-' + tone(col.key, row[col.key]);
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });

    if (status) {
      status.textContent =
        rows.length + ' von ' + state.rows.length + ' Ländern · Quelle ' + state.url;
    }
    if (missing) {
      missing.hidden = state.hasRealunit;
    }
    state.visible = rows;
    var ready = rows.length > 0;
    ['geo-filter-csv', 'geo-filter-xls', 'geo-filter-pdf'].forEach(function (id) {
      var btn = $(id);
      if (btn) btn.disabled = !ready;
    });
  }

  function bindDownloads(state) {
    var csv = $('geo-filter-csv');
    var xls = $('geo-filter-xls');
    var pdf = $('geo-filter-pdf');
    if (csv) csv.addEventListener('click', function () { downloadCsv(state.visible || []); });
    if (xls) xls.addEventListener('click', function () { downloadExcel(state.visible || []); });
    if (pdf) pdf.addEventListener('click', function () { downloadPdf(state.visible || []); });
  }

  function init() {
    var root = $('geo-filter-live');
    if (!root) return;
    var status = $('geo-filter-status');
    if (status) status.textContent = 'Lade GET /v1/country …';

    load(URLS)
      .then(function (result) {
        var rows = result.body.map(rowView);
        var hasRealunit = result.body.some(function (country) {
          return country && country.realunit != null;
        });
        var state = { rows: rows, url: result.url, hasRealunit: hasRealunit, visible: rows };
        ['geo-filter-search', 'geo-filter-residence', 'geo-filter-nationality'].forEach(function (id) {
          var el = $(id);
          if (el) el.addEventListener('input', function () { render(state); });
          if (el) el.addEventListener('change', function () { render(state); });
        });
        bindDownloads(state);
        render(state);
      })
      .catch(function (err) {
        if (status) {
          status.textContent =
            'Tabelle konnte nicht geladen werden (' + (err && err.message ? err.message : err) + ').';
        }
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
