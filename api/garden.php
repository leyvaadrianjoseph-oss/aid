<?php
require __DIR__ . '/_bootstrap.php';
$method = method_is('GET', 'POST');
$me = require_user();
$uid = q($me['id']);

function garden_item(int $id): array {
    $rows = sb('GET', '/shop_items?id=eq.' . $id . '&is_active=eq.true&select=*');
    if (!$rows) fail('That item is not available', 404);
    return $rows[0];
}

function garden_spend(array $me, int $cost): int {
    $balance = (int)$me['seeds'];
    if ($balance < $cost) fail('Not enough seeds yet', 402);
    $paid = sb('PATCH', '/profiles?id=eq.' . q((string)$me['id']) . '&seeds=eq.' . $balance, ['seeds' => $balance - $cost]);
    if (!$paid) fail('Your seed balance changed. Try again.', 409);
    return $balance - $cost;
}

function garden_refund(array $me, int $balance): void {
    sb('PATCH', '/profiles?id=eq.' . q((string)$me['id']), ['seeds' => $balance]);
}

function garden_inventory_add(string $userId, int $itemId, int $amount): void {
    $uid = q($userId);
    $rows = sb('GET', '/garden_inventory?user_id=eq.' . $uid . '&item_id=eq.' . $itemId . '&select=id,quantity');
    if ($rows) {
        $old = (int)$rows[0]['quantity'];
        $updated = sb('PATCH', '/garden_inventory?id=eq.' . (int)$rows[0]['id'] . '&quantity=eq.' . $old, ['quantity' => $old + $amount]);
        if (!$updated) fail('Inventory changed. Please try again.', 409);
    } else {
        [$code] = sb_raw('POST', '/garden_inventory', ['user_id' => $userId, 'item_id' => $itemId, 'quantity' => $amount]);
        if ($code < 200 || $code >= 300) fail('Could not add the item to your inventory', 409);
    }
}

if ($method === 'GET') {
    [$code, $data] = sb_raw('POST', '/rpc/garden_load', ['p_user_id' => $me['id']]);
    if ($code < 200 || $code >= 300 || !is_array($data)) fail('Could not load your garden data', 500);
    json_out($data);
}

$in = read_json();
$action = (string)($in['action'] ?? 'plant');
$itemId = int_in($in, 'item_id', 1, 1000000, 0);
$item = garden_item($itemId);
$kind = (string)$item['kind'];

if ($action === 'harvest') {
    if ($kind !== 'seed') fail('Only planted crops can be harvested.');
    $slot = int_in($in, 'slot', 0, 11, -1);
    [$code, $result] = sb_raw('POST', '/rpc/garden_harvest', [
        'p_user_id' => $me['id'],
        'p_item_id' => $itemId,
        'p_slot' => $slot
    ]);
    if ($code < 200 || $code >= 300) {
        $message = is_array($result) ? (string)($result['message'] ?? $result['details'] ?? '') : '';
        if (stripos($message, 'not mature') !== false) fail('This plant is not ready to harvest yet.', 409);
        if (stripos($message, 'plant not found') !== false) fail('That plant is no longer in this plot.', 404);
        fail('Could not harvest this plant. Please reload your garden.', 409);
    }
    json_out($result);
}

if ($action === 'plant') {
    if (!array_key_exists('slot', $in)) fail('Pick an empty plot first.');
    if ($kind !== 'seed') fail('Choose a seed to plant.');
    $slot = int_in($in, 'slot', 0, 11, -1);
    [$code, $result] = sb_raw('POST', '/rpc/garden_plant', [
        'p_user_id' => $me['id'],
        'p_item_id' => $itemId,
        'p_slot' => $slot
    ]);
    if ($code < 200 || $code >= 300) {
        $message = is_array($result) ? (string)($result['message'] ?? $result['details'] ?? '') : '';
        if (stripos($message, 'daily purchase limit') !== false) fail('You reached your daily limit of 100 items. Come back tomorrow!', 429);
        if (stripos($message, 'not enough seeds') !== false) fail('Not enough seeds yet.', 402);
        if (stripos($message, 'already planted') !== false) fail('That plot is already planted.', 409);
        if (stripos($message, 'no seeds of this type') !== false) fail('Buy this seed first and make sure it is in your inventory.', 409);
        fail('Could not plant there. Please try again.', 409);
    }
    json_out($result, 201);
}

if ($action === 'purchase') {
    $quantity = int_in($in, 'quantity', 1, 100, 1);
    [$code, $result] = sb_raw('POST', '/rpc/garden_purchase', [
        'p_user_id' => $me['id'],
        'p_item_id' => $itemId,
        'p_quantity' => $quantity
    ]);
    if ($code < 200 || $code >= 300) {
        $message = is_array($result) ? (string)($result['message'] ?? $result['details'] ?? '') : '';
        if (stripos($message, 'daily purchase limit') !== false) fail('You reached your daily limit of 100 items. Come back tomorrow!', 429);
        if (stripos($message, 'not enough seeds') !== false) fail('Not enough seeds yet.', 402);
        if (stripos($message, 'already own this tool') !== false) fail('You already own this tool.', 409);
        if (stripos($message, 'not available') !== false) fail('That item is not available.', 404);
        fail('Could not complete this purchase. Please try again.', 409);
    }
    if (!is_array($result)) fail('Purchase completed, but the response was invalid. Reload your garden.', 500);
    json_out($result, 201);
}

if ($action === 'water') {
    if (!array_key_exists('slot', $in)) fail('Choose a plant to water.');
    if ($kind !== 'seed') fail('Only planted crops can be watered.');
    $tool = sb('GET', '/shop_items?is_active=eq.true&sprite=eq.can&select=id');
    if (!$tool) fail('Watering can is unavailable.');
    $toolId = (int)$tool[0]['id'];
    $owned = sb('GET', '/garden_inventory?user_id=eq.' . $uid . '&item_id=eq.' . $toolId . '&select=quantity');
    if (!$owned || (int)$owned[0]['quantity'] < 1) fail('Buy a watering can from the shop first.');
    $slot = int_in($in, 'slot', 0, 11, -1);
    $rows = sb('GET', '/garden_plots?user_id=eq.' . $uid . '&slot=eq.' . $slot . '&select=id,item_id,planted_at,growth_bonus_seconds,last_watered_at');
    if (!$rows || (int)$rows[0]['item_id'] !== $itemId) fail('That plant is not in this plot.', 404);
    $plot = $rows[0];
    $elapsed = max(0, time() - strtotime((string)$plot['planted_at']));
    $duration = max(60, (int)$item['growth_seconds']);
    $bonus = (int)$plot['growth_bonus_seconds'];
    $remaining = $duration - $elapsed - $bonus;
    if ($remaining <= 0) fail('This plant is already fully grown.');
    if (!empty($plot['last_watered_at']) && time() - strtotime((string)$plot['last_watered_at']) < 60) fail('This plant was watered recently. Try again in a minute.');
    $boost = min(60, max(0, $remaining - 1));
    $updated = sb('PATCH', '/garden_plots?id=eq.' . (int)$plot['id'] . '&growth_bonus_seconds=eq.' . $bonus, ['growth_bonus_seconds' => $bonus + $boost, 'last_watered_at' => gmdate('c')]);
    if (!$updated) fail('The plant changed. Try watering again.', 409);
    json_out(['ok' => true, 'action' => 'water', 'boost_seconds' => $boost]);
}

if ($action === 'replace_decor') {
    if ($kind !== 'decor') fail('Choose a decoration to place.');
    $area = (string)($in['area'] ?? '');
    if (!in_array($area, ['fence', 'decor'], true)) fail('Invalid decoration area.');
    $slot = int_in($in, 'slot', 0, $area === 'fence' ? 7 : 3, -1);
    if (($item['sprite'] === 'fence') !== ($area === 'fence')) fail('That decoration belongs in a different area.');
    [$code, $result] = sb_raw('POST', '/rpc/garden_replace_decor', [
        'p_user_id' => $me['id'],
        'p_new_item_id' => $itemId,
        'p_area' => $area,
        'p_slot' => $slot
    ]);
    if ($code < 200 || $code >= 300) {
        $message = is_array($result) ? (string)($result['message'] ?? $result['details'] ?? '') : '';
        if (stripos($message, 'not in inventory') !== false) fail('You need one of that item in your inventory before replacing this space.', 409);
        if (stripos($message, 'decoration not found') !== false) fail('That decoration has already moved. Reload your garden.', 404);
        fail('Could not replace that decoration. Please try again.', 409);
    }
    json_out($result);
}

if ($action === 'pickup_decor') {
    if ($kind !== 'decor') fail('Choose a decoration to pick up.');
    $area = (string)($in['area'] ?? '');
    if (!in_array($area, ['fence', 'decor'], true)) fail('Invalid decoration area.');
    $slot = int_in($in, 'slot', 0, $area === 'fence' ? 7 : 3, -1);
    if (($item['sprite'] === 'fence') !== ($area === 'fence')) fail('That decoration is in a different area.');
    [$code, $result] = sb_raw('POST', '/rpc/garden_pickup_decor', [
        'p_user_id' => $me['id'],
        'p_item_id' => $itemId,
        'p_area' => $area,
        'p_slot' => $slot
    ]);
    if ($code < 200 || $code >= 300) {
        $message = is_array($result) ? (string)($result['message'] ?? $result['details'] ?? '') : '';
        if (stripos($message, 'decoration not found') !== false) fail('That decoration has already moved.', 404);
        fail('Could not return the decoration to inventory.', 409);
    }
    json_out($result);
}

if ($action === 'place_decor') {
    if (!array_key_exists('slot', $in)) fail('Choose a decoration space.');
    if ($kind !== 'decor') fail('Choose a decoration.');
    $area = $item['sprite'] === 'fence' ? 'fence' : 'decor';
    $slot = int_in($in, 'slot', 0, $area === 'fence' ? 7 : 3, -1);
    if (sb('GET', '/garden_decor?user_id=eq.' . $uid . '&area=eq.' . $area . '&slot=eq.' . $slot . '&select=id')) fail('That decoration space is occupied.', 409);
    $owned = sb('GET', '/garden_inventory?user_id=eq.' . $uid . '&item_id=eq.' . $itemId . '&select=id,quantity');
    if (!$owned || (int)$owned[0]['quantity'] < 1) fail('Buy this decoration first.');
    $inventoryId = (int)$owned[0]['id'];
    $quantity = (int)$owned[0]['quantity'];
    $updated = sb('PATCH', '/garden_inventory?id=eq.' . $inventoryId . '&quantity=eq.' . $quantity, ['quantity' => $quantity - 1]);
    if (!$updated) fail('Inventory changed. Try again.', 409);
    [$code] = sb_raw('POST', '/garden_decor', ['user_id' => $me['id'], 'area' => $area, 'slot' => $slot, 'item_id' => $itemId]);
    if ($code < 200 || $code >= 300) {
        sb('PATCH', '/garden_inventory?id=eq.' . $inventoryId, ['quantity' => $quantity]);
        fail('Could not place the decoration. Item returned to inventory.', 409);
    }
    json_out(['ok' => true, 'action' => 'place_decor', 'area' => $area, 'slot' => $slot, 'item_id' => $itemId], 201);
}

fail('Unknown garden action.', 422);
?>
