/* UGW website: smooth page changes, quick-view side panel, alerts menu and toasts.
   Every page still works without this script; it only avoids full page reloads. */
(function () {
  const progress = document.getElementById('progress');
  const drawer = document.getElementById('drawer');
  const overlay = document.getElementById('overlay');
  const drawerBody = document.getElementById('drawer-body');

  function busy(on) { progress.classList.toggle('on', on); }

  function runScripts(root) {
    root.querySelectorAll('script').forEach(old => {
      const s = document.createElement('script');
      s.textContent = old.textContent;
      old.replaceWith(s);
    });
  }

  function afterRender() {
    document.querySelectorAll('.toast').forEach((t, i) => {
      setTimeout(() => t.classList.add('show'), 30 + i * 80);
      setTimeout(() => t.classList.remove('show'), 4200 + i * 80);
    });
  }

  async function swap(url, options = {}, push = true) {
    busy(true);
    try {
      const res = await fetch(url, Object.assign({ headers: { 'X-Requested-With': 'fetch' } }, options));
      const html = await res.text();
      const doc = new DOMParser().parseFromString(html, 'text/html');
      const main = doc.querySelector('.main'), nav = doc.querySelector('.nav');
      if (!main) { window.location.href = res.url; return; }
      closeDrawer();
      document.querySelector('.main').innerHTML = main.innerHTML;
      if (nav) document.querySelector('.nav').innerHTML = nav.innerHTML;
      document.title = doc.title;
      if (push) history.pushState({}, '', res.url);
      runScripts(document.querySelector('.main'));
      window.scrollTo({ top: 0 });
      document.querySelector('.content').classList.add('enter');
      afterRender();
    } catch (err) {
      window.location.href = url;
    } finally {
      busy(false);
    }
  }

  function internal(a) {
    if (!a || a.target || a.hasAttribute('download') || a.dataset.native !== undefined) return false;
    const href = a.getAttribute('href') || '';
    if (!href || href.startsWith('#') || href.startsWith('mailto:') || href.startsWith('tel:')) return false;
    const u = new URL(a.href, location.href);
    return u.origin === location.origin && !u.pathname.startsWith('/static/');
  }

  /* ---- quick-view side panel */
  async function openDrawer(url) {
    busy(true);
    try {
      const res = await fetch(url, { headers: { 'X-Requested-With': 'fetch' } });
      drawerBody.innerHTML = await res.text();
      drawer.classList.add('open'); overlay.classList.add('open');
      drawer.setAttribute('aria-hidden', 'false');
      drawerBody.scrollTop = 0;
    } finally { busy(false); }
  }
  function closeDrawer() {
    drawer.classList.remove('open'); overlay.classList.remove('open');
    drawer.setAttribute('aria-hidden', 'true');
  }
  overlay.addEventListener('click', closeDrawer);
  drawer.querySelector('.drawer-close').addEventListener('click', closeDrawer);

  document.addEventListener('click', e => {
    // close the alerts menu when clicking elsewhere
    document.querySelectorAll('.bell-wrap.open').forEach(w => { if (!w.contains(e.target)) w.classList.remove('open'); });

    const row = e.target.closest('[data-peek]');
    if (row && !e.target.closest('a, button, input, select, label')) {
      e.preventDefault();
      openDrawer(row.dataset.peek);
      return;
    }
    const a = e.target.closest('a');
    if (a && internal(a) && !e.ctrlKey && !e.metaKey && !e.shiftKey && e.button === 0) {
      e.preventDefault();
      swap(a.href);
    }
  });

  document.addEventListener('submit', e => {
    const form = e.target;
    if (e.defaultPrevented || form.target || form.dataset.native !== undefined) return;
    e.preventDefault();
    const data = new FormData(form);
    if (e.submitter && e.submitter.name) data.append(e.submitter.name, e.submitter.value);
    const method = (form.getAttribute('method') || 'get').toUpperCase();
    const action = form.getAttribute('action') || location.pathname;
    if (method === 'GET') {
      const u = new URL(action, location.href);
      u.search = new URLSearchParams(data).toString();
      swap(u.toString());
    } else {
      swap(action, { method: 'POST', body: data });
    }
  });

  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') { closeDrawer(); document.querySelectorAll('.bell-wrap.open').forEach(w => w.classList.remove('open')); }
    if (e.key === '/' && !/input|textarea|select/i.test(document.activeElement.tagName)) {
      e.preventDefault(); const s = document.querySelector('.topbar input'); if (s) s.focus();
    }
  });

  window.addEventListener('popstate', () => swap(location.href, {}, false));
  afterRender();
})();

/* ---- live interactions, re-applied after every page change */
(function () {
  const fmt = v => '$' + (Math.round(v * 100) / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  function initPage() {
    // type-to-filter tables
    document.querySelectorAll('[data-live]').forEach(inp => {
      const table = document.querySelector(inp.dataset.live); if (!table || inp._live) return; inp._live = true;
      const run = () => {
        const t = inp.value.trim().toLowerCase(); let n = 0;
        table.querySelectorAll('tbody tr').forEach(tr => { const ok = !t || tr.innerText.toLowerCase().includes(t); tr.hidden = !ok; if (ok) n++; });
      };
      inp.addEventListener('input', run);
    });
    // quotation form: running total
    const qf = document.querySelector('form [name="price1"]');
    if (qf && !qf.form._total) {
      const form = qf.form; form._total = true;
      const out = document.createElement('div'); out.className = 'total-pill'; out.style.display = 'inline-block'; out.style.marginLeft = '10px';
      const addBtn = [...form.querySelectorAll('button[type=button]')].find(b => b.textContent.includes('Add line'));
      if (addBtn) addBtn.after(out);
      const calc = () => {
        let s = 0; form.querySelectorAll('.line-row[data-i]').forEach(r => { if (!r.hidden && r.querySelector('select').value) s += parseFloat(r.querySelector('[name^=price]').value || 0); });
        out.textContent = 'Quoted total ' + fmt(s);
      };
      form.addEventListener('input', calc); form.addEventListener('click', () => setTimeout(calc, 0)); calc();
    }
    // convert-to-booking: show supplier cost and UGW income per line
    document.querySelectorAll('input[name^="fee"]').forEach(inp => {
      if (inp._split) return; inp._split = true;
      const row = inp.closest('tr'); const quoted = parseFloat(row.querySelector('td.num').textContent.replace(/[$,]/g, ''));
      const hint = document.createElement('div'); hint.className = 'live-hint'; inp.after(hint);
      const upd = () => { const fee = parseFloat(inp.value || 0); hint.innerHTML = 'Supplier cost <b>' + fmt(quoted - fee) + '</b>'; };
      inp.addEventListener('input', upd); upd();
    });
    // payment form: remaining after this payment
    const amt = document.getElementById('amt'), sel = document.getElementById('inv');
    if (amt && sel && !amt._rem) {
      amt._rem = true; const hint = document.createElement('div'); hint.className = 'live-hint'; amt.after(hint);
      const upd = () => {
        const left = parseFloat(sel.selectedOptions[0].dataset.left || 0), a = parseFloat(amt.value || 0);
        hint.innerHTML = 'Still due on this invoice: <b>' + fmt(left) + '</b> → after this payment: <b>' + fmt(left - a) + '</b>';
      };
      amt.addEventListener('input', upd); sel.addEventListener('change', () => setTimeout(upd, 0)); upd();
    }
    // modification form: show the fields of the chosen type and the total charge
    document.querySelectorAll('[data-modform]').forEach(form => {
      if (form._mod) return; form._mod = true;
      const type = form.querySelector('[data-modtype]');
      const show = () => form.querySelectorAll('[data-when]').forEach(d => { d.hidden = d.dataset.when !== type.value; });
      const bal0 = parseFloat(form.dataset.balance || 0);
      const charge = () => {
        let s = 0; form.querySelectorAll('[data-fee]').forEach(i => s += Math.max(0, parseFloat(i.value || 0)));
        form.querySelector('[data-charge]').textContent = fmt(s);
        let cancelled = 0;
        if (type.value === 'Cancellation') form.querySelectorAll('input[name=services]:checked').forEach(c => cancelled += parseFloat(c.dataset.price || 0));
        const refund = Math.max(0, parseFloat((form.querySelector('[name=refundToClient]') || {}).value || 0));
        let delta = 0;
        const svc = form.querySelector('[data-svc]'), np = form.querySelector('[name=newPrice]');
        if (type.value === 'Change' && svc && svc.value && np && np.value !== '') delta = parseFloat(np.value) - parseFloat(svc.selectedOptions[0].dataset.price || 0);
        cancelled -= delta;
        const after = bal0 - cancelled + s + refund;
        // suggested refund: what the client has overpaid once this change is applied
        const overpaid = Math.max(0, -(bal0 - cancelled + s));
        const sug = form.querySelector('[data-suggest]');
        if (sug) { sug.hidden = !(overpaid > 0.004) || Math.abs(overpaid - refund) < 0.005; sug.textContent = 'Refund what the client overpaid: ' + fmt(overpaid); sug.dataset.v = overpaid.toFixed(2); }
        const dw = form.querySelector('[data-deduct-wrap]'), dd = form.querySelector('[data-deduct]');
        if (dw) { const show = s > 0 && refund > 0; dw.hidden = !show; if (!show) dd.checked = false; else if (!dd._touched) dd.checked = true; }
        const eff = form.querySelector('[data-effect]');
        if (eff) eff.innerHTML = (delta ? 'price ' + (delta > 0 ? '+' : '−') + fmt(Math.abs(delta)) + ' · ' : '') + (cancelled + delta ? 'cancelled services −' + fmt(cancelled + delta) + ' · ' : '') + (s ? 'charge +' + fmt(s) + ' · ' : '') + (refund ? 'refund +' + fmt(refund) + ' · ' : '') +
          'balance after: <b>' + (after < 0 ? fmt(-after) + ' refund due to client' : fmt(after) + ' due') + '</b>';
      };
      const sugBtn = form.querySelector('[data-suggest]');
      if (sugBtn) sugBtn.addEventListener('click', () => { form.querySelector('[name=refundToClient]').value = sugBtn.dataset.v; charge(); });
      const ddBox = form.querySelector('[data-deduct]'); if (ddBox) ddBox.addEventListener('change', () => { ddBox._touched = true; });
      type.addEventListener('change', () => { show(); charge(); }); form.addEventListener('input', charge); form.addEventListener('change', charge); show(); charge();
      form.addEventListener('submit', e => {
        if (type.value !== 'Cancellation') return;
        const boxes = form.querySelectorAll('input[name=services]'), ticked = form.querySelectorAll('input[name=services]:checked');
        const refund = parseFloat((form.querySelector('[name=refundToClient]') || {}).value || 0);
        if (!ticked.length && !refund) { e.preventDefault(); alert('Tick the service(s) the client cancels.'); return; }
        if (boxes.length && ticked.length === boxes.length && !confirm('All services are ticked: this cancels the WHOLE booking. Continue?')) e.preventDefault();
      });
    });
  }
  window.ugwInit = initPage;
  initPage();
  new MutationObserver(() => initPage()).observe(document.querySelector('.main'), { childList: true });
})();
