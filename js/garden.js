/* Inside the Garden: persistent planting, inventory selection and visible placement. */
(function () {
  'use strict';
  const PG = window.PG;
  const landEl = document.getElementById('land-plots');
  if (!landEl) return;

  const waterEl = document.getElementById('water-plots');
  const shopEl = document.getElementById('shop');
  const msg = document.getElementById('garden-msg');
  const inventoryEl = document.getElementById('inventory');
  const selectedEl = document.getElementById('selected-item');
  const inventoryCount = document.getElementById('inventory-count');
  const fenceEl = document.getElementById('fence-slots');
  const decorEl = document.getElementById('decor-slots');
  const clockIcon = document.getElementById('garden-time-icon');
  const clockName = document.getElementById('garden-time-name');
  const clockCountdown = document.getElementById('garden-time-countdown');

  let items = [], plots = {}, inventory = {}, decor = [], seeds = 0;
  let selectedId = null, selectedAction = null, busy = false;
  const byId = (id) => items.find((item) => Number(item.id) === Number(id));
  const owned = (id) => Number(inventory[id] || 0);
  const elapsedSeconds = (stamp) => Math.max(0, Math.floor(Date.now() / 1000 - new Date(stamp).getTime() / 1000));

  function say(message, error) {
    msg.textContent = message;
    msg.classList.toggle('is-error', !!error);
  }

  function selectedItem() { return selectedId === null ? null : byId(selectedId); }
  function canId() {
    const can = items.find((item) => item.sprite === 'can');
    return can ? Number(can.id) : -1;
  }

  function growth(plot, item) {
    const duration = Math.max(60, Number(item.growth_seconds || 300));
    const elapsed = elapsedSeconds(plot.planted_at) + Number(plot.growth_bonus_seconds || 0);
    const progress = Math.min(1, elapsed / duration);
    return { progress, stage: progress >= 1 ? 'Mature' : progress >= .5 ? 'Growing' : 'Seedling', percent: Math.floor(progress * 100) };
  }

  function itemButton(item, count, action) {
    const active = selectedId === Number(item.id);
    const button = PG.el('button', 'inventory-card' + (active ? ' is-selected' : ''));
    button.type = 'button';
    button.setAttribute('aria-pressed', active ? 'true' : 'false');
    button.appendChild(PG.spriteEl(item.sprite, 'inventory-sprite'));
    const meta = PG.el('span', 'inventory-card-meta');
    meta.appendChild(PG.el('strong', null, item.name));
    meta.appendChild(PG.el('small', null, '× ' + count));
    button.appendChild(meta);
    button.addEventListener('click', () => selectItem(item, action));
    return button;
  }

  function selectItem(item, action) {
    selectedId = Number(item.id);
    selectedAction = action;
    renderSelection();
    renderInventory();
    renderShop();
    renderPlots();
    renderDecor();
    if (action === 'plant') say('Selected ' + item.name + '. Tap an empty land or water plot to plant it.');
    else if (action === 'water') say('Watering can selected. Tap a growing plant to boost it.');
    else say('Selected ' + item.name + '. Tap a highlighted fence or decoration space to place it.');
  }

  function renderSelection() {
    selectedEl.textContent = '';
    const item = selectedItem();
    if (!item) {
      selectedEl.className = 'selected-item';
      selectedEl.append(PG.el('div', 'selected-item-icon', '✦'));
      const copy = PG.el('div');
      copy.append(PG.el('strong', null, 'No item selected'));
      copy.append(PG.el('p', null, 'Choose an item below to preview it.'));
      selectedEl.append(copy);
      return;
    }
    selectedEl.className = 'selected-item has-selection';
    selectedEl.append(PG.spriteEl(item.sprite, 'selected-preview-sprite'));
    const copy = PG.el('div', 'selected-item-copy');
    copy.append(PG.el('strong', null, item.name));
    const description = selectedAction === 'plant' ? 'Ready to plant · tap an empty plot'
      : selectedAction === 'water' ? 'Reusable tool · tap a growing plant'
      : 'Ready to place · tap a highlighted space';
    copy.append(PG.el('p', null, description));
    selectedEl.append(copy);
    const clear = PG.el('button', 'clear-selection', '×');
    clear.type = 'button';
    clear.setAttribute('aria-label', 'Clear selected item');
    clear.addEventListener('click', () => {
      selectedId = null; selectedAction = null;
      renderSelection(); renderInventory(); renderShop(); renderPlots(); renderDecor();
      say('Selection cleared. Choose another item.');
    });
    selectedEl.append(clear);
  }

  function renderInventory() {
    inventoryEl.textContent = '';
    const ownedItems = items.filter((item) => item.kind !== 'seed' && owned(item.id) > 0);
    inventoryCount.textContent = String(ownedItems.reduce((sum, item) => sum + owned(item.id), 0));
    if (!ownedItems.length) {
      inventoryEl.append(PG.el('p', 'inventory-empty', 'Your tools and decorations will appear here after you buy them.'));
      return;
    }
    ownedItems.forEach((item) => {
      const action = item.kind === 'tool' ? 'water' : 'decor';
      inventoryEl.append(itemButton(item, owned(item.id), action));
    });
  }

  function renderPlots() {
    function renderGroup(root, start, end, water) {
      root.textContent = '';
      for (let slot = start; slot < end; slot++) {
        const plot = plots[slot];
        const item = plot ? byId(plot.item_id) : null;
        const button = PG.el('button', 'plot ' + (water ? 'water-plot' : 'land-plot'));
        button.type = 'button';
        if (item && item.kind === 'seed') {
          const state = growth(plot, item);
          button.classList.add('is-planted', 'plant-' + state.stage.toLowerCase());
          button.append(PG.spriteEl(item.sprite, 'plant-sprite'));
          button.append(PG.el('span', 'plant-details', state.stage + ' · ' + state.percent + '%'));
          button.setAttribute('aria-label', item.name + ', ' + state.percent + '% grown, plot ' + (slot + 1));
          button.addEventListener('click', () => {
            if (selectedAction === 'water' && selectedItem() && owned(canId()) > 0) {
              water(slot, Number(item.id));
            } else if (selectedAction === 'plant') {
              PG.toast('That plot is occupied. Choose an empty plot.', true);
            } else if (owned(canId()) > 0) {
              water(slot, Number(item.id));
            } else {
              selectItem(byId(canId()) || item, 'water');
              PG.toast('Choose or buy a watering can to water this plant.');
            }
          });
        } else if (item) {
          button.classList.add('is-legacy');
          button.append(PG.spriteEl(item.sprite));
          button.append(PG.el('span', 'plant-details', item.name));
          button.disabled = true;
        } else {
          button.classList.add('is-empty');
          button.append(PG.el('span', 'plot-plus', '+'));
          button.append(PG.el('small', 'plot-number', String(slot - start + 1)));
          const canPlant = selectedAction === 'plant' && selectedItem();
          if (canPlant) button.classList.add('is-target');
          button.addEventListener('click', () => plant(slot));
        }
        root.append(button);
      }
    }
    renderGroup(landEl, 0, 8, false);
    renderGroup(waterEl, 8, 12, true);
  }

  function renderDecorArea(area, root, count) {
    root.textContent = '';
    for (let slot = 0; slot < count; slot++) {
      const placed = decor.find((entry) => entry.area === area && Number(entry.slot) === slot);
      const item = placed ? byId(placed.item_id) : null;
      const button = PG.el('button', 'garden-decor-slot' + (item ? ' is-filled' : '') + (selectedAction === 'decor' && !item ? ' is-target' : ''));
      button.type = 'button';
      if (item) {
        button.append(PG.spriteEl(item.sprite, 'decor-sprite'));
        button.append(PG.el('small', 'decor-name', item.name));
        button.setAttribute('aria-label', item.name + ' placed');
      } else {
        button.append(PG.el('span', 'decor-plus', '+'));
        button.append(PG.el('small', null, area === 'fence' ? 'Fence' : 'Decor'));
        button.addEventListener('click', () => placeDecor(slot, area));
      }
      root.append(button);
    }
  }

  function renderDecor() {
    renderDecorArea('fence', fenceEl, 8);
    renderDecorArea('decor', decorEl, 4);
  }

  function renderShop() {
    shopEl.textContent = '';
    items.forEach((item) => {
      const isOwnedTool = item.kind === 'tool' && owned(item.id) > 0;
      const poor = seeds < Number(item.cost_seeds);
      const card = PG.el('div', 'shop-item' + (selectedId === Number(item.id) ? ' is-selected' : ''));
      card.append(PG.spriteEl(item.sprite, 'shop-sprite'));
      const info = PG.el('div', 'shop-item-info');
      info.append(PG.el('strong', null, item.name));
      info.append(PG.el('small', null, item.cost_seeds + ' seeds' + (item.kind === 'seed' ? ' · ' + Math.ceil(Number(item.growth_seconds || 300) / 60) + ' min' : '')));
      card.append(info);
      const button = PG.el('button', 'shop-action', item.kind === 'seed' ? 'Select' : isOwnedTool ? 'Owned' : 'Buy');
      button.type = 'button';
      button.disabled = item.kind === 'seed' ? false : (poor || isOwnedTool);
      button.addEventListener('click', () => {
        if (item.kind === 'seed') selectItem(item, 'plant');
        else purchase(item);
      });
      card.append(button);
      shopEl.append(card);
    });
  }

  function refreshBalance(balance) {
    seeds = Number(balance);
    PG.setStats({ seeds });
    renderShop();
  }

  async function reloadGarden() {
    const data = await PG.api('/api/garden.php');
    items = data.items || [];
    plots = {};
    (data.plots || []).forEach((plot) => { plots[Number(plot.slot)] = plot; });
    inventory = {};
    (data.inventory || []).forEach((row) => { inventory[Number(row.item_id)] = Number(row.quantity); });
    decor = data.decor || [];
    seeds = Number(data.seeds || 0);
    PG.setStats({ seeds });
    if (selectedId !== null && !byId(selectedId)) { selectedId = null; selectedAction = null; }
    renderSelection(); renderPlots(); renderInventory(); renderDecor(); renderShop();
  }

  async function runAction(task, successMessage) {
    if (busy) return;
    busy = true;
    document.body.classList.add('garden-busy');
    try {
      await task();
      await reloadGarden();
      say(successMessage);
      PG.toast(successMessage);
    } catch (error) {
      say(error.message || 'Something went wrong. Try again.', true);
      PG.toast(error.message || 'Something went wrong.', true);
    } finally {
      busy = false;
      document.body.classList.remove('garden-busy');
    }
  }

  async function plant(slot) {
    const item = selectedItem();
    if (!item || selectedAction !== 'plant' || item.kind !== 'seed') {
      say('Choose a seed from the shop first.', true); return;
    }
    await runAction(() => PG.api('/api/garden.php', { method: 'POST', body: { action: 'plant', item_id: item.id, slot } }), item.name + ' planted in plot ' + (slot + 1) + '.');
  }

  async function purchase(item) {
    await runAction(() => PG.api('/api/garden.php', { method: 'POST', body: { action: 'purchase', item_id: item.id } }), item.name + ' added to your inventory.');
  }

  async function water(slot, itemId) {
    const item = byId(itemId);
    if (busy) return;
    await runAction(() => PG.api('/api/garden.php', { method: 'POST', body: { action: 'water', item_id: itemId, slot } }), item.name + ' watered. Growth boosted!');
  }

  async function placeDecor(slot, targetArea) {
    const item = selectedItem();
    if (!item || selectedAction !== 'decor' || item.kind !== 'decor') {
      say('Choose a decoration from your inventory first.', true); return;
    }
    const area = item.sprite === 'fence' ? 'fence' : 'decor';
    if (targetArea !== area) {
      say(item.sprite === 'fence' ? 'Fences can only go on the fence line.' : 'Lanterns and ponds go in the garden decor spaces.', true);
      return;
    }
    await runAction(() => PG.api('/api/garden.php', { method: 'POST', body: { action: 'place_decor', item_id: item.id, slot } }), item.name + ' placed in your garden.');
  }

  function updateClock() {
    const now = Math.floor(Date.now() / 1000);
    const left = 300 - (now % 300);
    const night = Math.floor(now / 300) % 2 === 1;
    document.body.classList.toggle('garden-night', night);
    clockIcon.textContent = night ? '🌙' : '☀️';
    clockName.textContent = night ? 'Nighttime' : 'Daytime';
    clockCountdown.textContent = String(Math.floor(left / 60)).padStart(2, '0') + ':' + String(left % 60).padStart(2, '0') + (night ? ' until day' : ' until night');
  }

  PG.ready.then(async (me) => {
    if (!me) return;
    try {
      await reloadGarden();
      say('Choose a seed to plant, or select a tool or decoration from your inventory.');
      updateClock();
      window.setInterval(() => { updateClock(); renderPlots(); }, 1000);
    } catch (error) {
      say(error.message || 'Could not load your garden.', true);
      PG.toast(error.message || 'Could not load your garden.', true);
    }
  });
  window.setInterval(updateClock, 1000);
})();
