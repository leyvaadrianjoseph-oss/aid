/* Inside the Garden: crops, watering, decorations and a shared day/night clock. */
(function () {
  'use strict';
  const PG = window.PG;
  const plotsEl = document.getElementById('plots');
  if (!plotsEl) return;

  const shopEl = document.getElementById('shop');
  const msg = document.getElementById('garden-msg');
  const inventoryEl = document.getElementById('inventory');
  const fenceEl = document.getElementById('fence-slots');
  const decorEl = document.getElementById('decor-slots');
  const clockIcon = document.getElementById('garden-time-icon');
  const clockName = document.getElementById('garden-time-name');
  const clockCountdown = document.getElementById('garden-time-countdown');

  let items = [], plots = {}, inventory = {}, decor = [], seeds = 0, selected = null, selectedAction = 'plant';
  const byId = (id) => items.find((i) => Number(i.id) === Number(id));
  const owned = (id) => Number(inventory[id] || 0);
  const elapsedSeconds = (stamp) => Math.max(0, Math.floor(Date.now() / 1000 - new Date(stamp).getTime() / 1000));

  function growth(plot, item) {
    const duration = Math.max(60, Number(item.growth_seconds || 300));
    const elapsed = elapsedSeconds(plot.planted_at) + Number(plot.growth_bonus_seconds || 0);
    const progress = Math.min(1, elapsed / duration);
    return { progress, stage: progress >= 1 ? 'Mature' : progress >= .5 ? 'Growing' : 'Seedling', percent: Math.floor(progress * 100) };
  }

  function renderPlots() {
    plotsEl.textContent = '';
    for (let slot = 0; slot < 12; slot++) {
      const plot = plots[slot];
      const item = plot ? byId(plot.item_id) : null;
      if (item && item.kind === 'seed') {
        const state = growth(plot, item);
        const b = PG.el('button', 'plot is-planted plant-' + state.stage.toLowerCase());
        b.type = 'button';
        b.setAttribute('aria-label', 'Plot ' + (slot + 1) + ': ' + item.name + ', ' + state.stage + ', ' + state.percent + '% grown. Select to water.');
        const plant = PG.spriteEl(item.sprite, 'plant-sprite');
        b.appendChild(plant);
        const details = PG.el('span', 'plant-details', state.stage + ' · ' + state.percent + '%');
        b.appendChild(details);
        if (selectedAction === 'water' && selected === Number(item.id)) b.classList.add('is-water-target');
        b.addEventListener('click', () => {
          if (owned(canId()) < 1) { PG.toast('Buy a watering can first.', true); return; }
          if (state.progress >= 1) { PG.toast('This plant is already fully grown.'); return; }
          water(slot, Number(item.id));
        });
        plotsEl.appendChild(b);
      } else {
        const b = PG.el('button', 'plot is-empty');
        b.type = 'button';
        b.setAttribute('aria-label', 'Plot ' + (slot + 1) + ', empty');
        b.appendChild(PG.el('span', 'plot-plus', '+'));
        b.addEventListener('click', () => plant(slot));
        plotsEl.appendChild(b);
      }
    }
  }

  function canId() {
    const can = items.find((i) => i.sprite === 'can');
    return can ? Number(can.id) : -1;
  }

  function renderDecorArea(area, root, count) {
    root.textContent = '';
    for (let slot = 0; slot < count; slot++) {
      const placed = decor.find((d) => d.area === area && Number(d.slot) === slot);
      const item = placed ? byId(placed.item_id) : null;
      const b = PG.el('button', 'garden-decor-slot' + (item ? ' is-filled' : ''));
      b.type = 'button';
      b.setAttribute('aria-label', area + ' space ' + (slot + 1) + (item ? ': ' + item.name : ', empty'));
      if (item) b.appendChild(PG.spriteEl(item.sprite));
      else b.textContent = '+';
      b.addEventListener('click', () => {
        if (!selected || selectedAction !== 'decor') { PG.toast('Choose a decoration from your inventory first.', true); return; }
        placeDecor(slot);
      });
      root.appendChild(b);
    }
  }

  function renderDecor() {
    renderDecorArea('fence', fenceEl, 8);
    renderDecorArea('decor', decorEl, 4);
  }

  function renderInventory() {
    inventoryEl.textContent = '';
    const ownedItems = items.filter((it) => owned(it.id) > 0);
    if (!ownedItems.length) {
      inventoryEl.appendChild(PG.el('p', 'muted', 'No tools or decorations yet. Buy them from the shop.'));
      return;
    }
    ownedItems.forEach((it) => {
      const row = PG.el('div', 'inventory-item');
      row.appendChild(PG.spriteEl(it.sprite));
      row.appendChild(PG.el('span', null, it.name + ' × ' + owned(it.id)));
      if (it.kind === 'tool') {
        const b = PG.el('button', 'px-btn px-btn--small ' + (selectedAction === 'water' ? 'px-btn--sun' : 'px-btn--ghost'), 'Water plants');
        b.type = 'button';
        b.disabled = it.sprite !== 'can';
        b.addEventListener('click', () => {
          selected = Number(it.id); selectedAction = 'water';
          msg.textContent = 'Watering can selected. Tap a growing plant to speed it up.';
          renderInventory(); renderPlots();
        });
        row.appendChild(b);
      } else if (it.kind === 'decor') {
        const b = PG.el('button', 'px-btn px-btn--small ' + (selected === Number(it.id) ? 'px-btn--sun' : 'px-btn--ghost'), 'Place');
        b.type = 'button';
        b.addEventListener('click', () => {
          selected = Number(it.id); selectedAction = 'decor';
          msg.textContent = it.sprite === 'fence' ? 'Choose one of the eight fence spaces.' : 'Choose one of the four decoration spaces.';
          renderInventory(); renderDecor();
        });
        row.appendChild(b);
      }
      inventoryEl.appendChild(row);
    });
  }

  function renderShop() {
    shopEl.textContent = '';
    items.forEach((it) => {
      const isOwnedTool = it.kind === 'tool' && owned(it.id) > 0;
      const poor = seeds < Number(it.cost_seeds);
      const card = PG.el('div', 'px-card shop-item' + (selected === Number(it.id) ? ' is-selected' : '') + (poor ? ' is-poor' : ''));
      card.appendChild(PG.spriteEl(it.sprite));
      const info = PG.el('div');
      info.appendChild(PG.el('h3', null, it.name));
      info.appendChild(PG.el('p', 'muted', it.cost_seeds + ' seeds · ' + it.kind + (it.kind === 'seed' ? ' · ' + Math.round(it.growth_seconds / 60) + ' min growth' : '')));
      card.appendChild(info);
      const label = it.kind === 'seed' ? 'Choose seed' : isOwnedTool ? 'Owned' : 'Buy';
      const button = PG.el('button', 'px-btn px-btn--small ' + (selected === Number(it.id) ? 'px-btn--sun' : 'px-btn--ghost'), label);
      button.type = 'button';
      button.disabled = poor || isOwnedTool;
      button.addEventListener('click', () => {
        if (it.kind === 'seed') {
          selected = Number(it.id); selectedAction = 'plant';
          msg.textContent = 'Tap an empty plot to plant ' + it.name.toLowerCase() + '.';
          renderShop();
        } else purchase(it);
      });
      card.appendChild(button);
      shopEl.appendChild(card);
    });
  }

  function refreshStats(balance) {
    seeds = Number(balance);
    PG.setStats({ seeds });
    renderShop();
  }

  async function plant(slot) {
    if (!selected || selectedAction !== 'plant') { PG.toast('Choose a seed first.', true); return; }
    const item = byId(selected);
    try {
      const r = await PG.api('/api/garden.php', { method: 'POST', body: { action: 'plant', item_id: item.id, slot } });
      plots[slot] = { slot, item_id: item.id, planted_at: new Date().toISOString(), growth_bonus_seconds: 0 };
      refreshStats(r.seeds); renderPlots(); renderInventory();
      msg.textContent = item.name + ' planted. Come back as it grows.';
      PG.toast('Planted: ' + item.name);
    } catch (e) { PG.toast(e.message, true); }
  }

  async function purchase(item) {
    try {
      const r = await PG.api('/api/garden.php', { method: 'POST', body: { action: 'purchase', item_id: item.id } });
      inventory[item.id] = owned(item.id) + 1;
      refreshStats(r.seeds); renderInventory();
      PG.toast('Purchased: ' + item.name);
    } catch (e) { PG.toast(e.message, true); }
  }

  async function water(slot, itemId) {
    try {
      const r = await PG.api('/api/garden.php', { method: 'POST', body: { action: 'water', item_id: itemId, slot } });
      plots[slot].growth_bonus_seconds = Number(plots[slot].growth_bonus_seconds || 0) + Number(r.boost_seconds || 0);
      renderPlots();
      PG.toast('Watered! Growth boosted by ' + r.boost_seconds + ' seconds.');
    } catch (e) { PG.toast(e.message, true); }
  }

  async function placeDecor(slot) {
    const item = byId(selected);
    if (!item) return;
    try {
      await PG.api('/api/garden.php', { method: 'POST', body: { action: 'place_decor', item_id: item.id, slot } });
      inventory[item.id] = Math.max(0, owned(item.id) - 1);
      decor.push({ area: item.sprite === 'fence' ? 'fence' : 'decor', slot, item_id: item.id });
      selected = null; selectedAction = 'plant';
      renderDecor(); renderInventory(); renderPlots();
      PG.toast('Placed: ' + item.name);
    } catch (e) { PG.toast(e.message, true); }
  }

  function updateClock() {
    const now = Math.floor(Date.now() / 1000);
    const cycle = 600;
    const phase = Math.floor(now / 300) % 2;
    const left = 300 - (now % 300);
    const night = phase === 1;
    document.body.classList.toggle('garden-night', night);
    clockIcon.textContent = night ? '🌙' : '☀️';
    clockName.textContent = night ? 'Nighttime' : 'Daytime';
    clockCountdown.textContent = String(Math.floor(left / 60)).padStart(2, '0') + ':' + String(left % 60).padStart(2, '0') + (night ? ' until day' : ' until night');
  }

  PG.ready.then((me) => {
    if (!me) return;
    PG.api('/api/garden.php').then((data) => {
      items = data.items || []; seeds = Number(data.seeds || 0);
      (data.plots || []).forEach((plot) => { plots[Number(plot.slot)] = plot; });
      (data.inventory || []).forEach((row) => { inventory[Number(row.item_id)] = Number(row.quantity); });
      decor = data.decor || [];
      PG.setStats({ seeds });
      renderPlots(); renderShop(); renderInventory(); renderDecor();
      msg.textContent = 'Choose a seed to plant, or use your tools and decorations from inventory.';
      updateClock(); window.setInterval(() => { updateClock(); renderPlots(); }, 1000);
    }).catch((e) => PG.toast(e.message, true));
  });
  updateClock();
  window.setInterval(updateClock, 1000);
})();
