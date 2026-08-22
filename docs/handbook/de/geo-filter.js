/**
 * Live RealUnit share-token geo-filter table.
 *
 * Source of truth is GET /v1/country (same payload the wallet uses). Rows are
 * never copied into this repo. Same-origin `/v1/country` is the handbook
 * nginx proxy; the public API is the fallback for a local file preview.
 */
(function () {
  var URLS = ['/v1/country', 'https://api.dfx.swiss/v1/country'];
  var COLUMNS = [
    { key: 'symbol', label: 'ISO' },
    { key: 'name', label: 'Land' },
    { key: 'residence', label: 'Wohnsitz' },
    { key: 'nationality', label: 'Nationalität' },
    { key: 'residenceExisting', label: 'Wohnsitz Bestand' },
    { key: 'nationalityExisting', label: 'Nationalität Bestand' },
    { key: 'ipEnable', label: 'IP neu' },
    { key: 'ipExisting', label: 'IP Bestand' },
    { key: 'taxEnable', label: 'Steuer neu' },
    { key: 'taxExisting', label: 'Steuer Bestand' },
  ];

  function $(id) {
    return document.getElementById(id);
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
    return {
      symbol: country.symbol,
      name: country.foreignName || country.name,
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

  function render(state) {
    var tbody = $('geo-filter-body');
    var status = $('geo-filter-status');
    var missing = $('geo-filter-missing');
    if (!tbody) return;

    var q = ($('geo-filter-search') || {}).value || '';
    q = q.trim().toLowerCase();
    var residence = ($('geo-filter-residence') || {}).value || '';
    var nationality = ($('geo-filter-nationality') || {}).value || '';

    var rows = state.rows.filter(function (row) {
      if (q && (row.symbol || '').toLowerCase().indexOf(q) < 0 && (row.name || '').toLowerCase().indexOf(q) < 0) {
        return false;
      }
      if (residence && row.residence !== residence) return false;
      if (nationality && row.nationality !== nationality) return false;
      return true;
    });

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
        var state = { rows: rows, url: result.url, hasRealunit: hasRealunit };
        ['geo-filter-search', 'geo-filter-residence', 'geo-filter-nationality'].forEach(function (id) {
          var el = $(id);
          if (el) el.addEventListener('input', function () { render(state); });
          if (el) el.addEventListener('change', function () { render(state); });
        });
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
