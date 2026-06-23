import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const events = JSON.parse(
  await readFile(new URL('fixtures/events.json', import.meta.url))
)
const eventTypes = [
  'start',
  'first_throttle',
  'checkpoint',
  'lap',
  'respawn',
  'finish',
  'end',
]
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

assert.deepEqual(
  events.map(event => event.type),
  eventTypes
)
const start = events.find(event => event.type === 'start')
const lap = events.find(event => event.type === 'lap')
const finish = events.find(event => event.type === 'finish')
assert.equal(start.players[0].login, 'player-one')
assert.equal(lap.checkpoint.checkpointLapIndex, 0)
assert.equal(
  finish.checkpoint.checkpointLapIndex,
  start.map.checkpointsPerLap + 1
)

function assertNoEmptyStrings(value, path = '$') {
  if (typeof value === 'string') {
    assert.notEqual(value, '', `${path} must not be an empty string`)
    return
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) =>
      assertNoEmptyStrings(item, `${path}[${index}]`)
    )
    return
  }
  if (value && typeof value === 'object') {
    for (const [key, child] of Object.entries(value)) {
      assertNoEmptyStrings(child, `${path}.${key}`)
    }
  }
}

function assertPlayer(player, index) {
  assert.ok(player)
  assert.equal(player.playerIndex, index)
  if ('name' in player) assert.equal(typeof player.name, 'string')
  if ('login' in player) {
    assert.equal(typeof player.login, 'string')
  }
  if ('localId' in player) {
    assert.equal(typeof player.localId, 'string')
  }
  if ('accountId' in player) {
    assert.equal(typeof player.accountId, 'string')
  }
}

for (const event of events) {
  assertNoEmptyStrings(event)
  assert.equal(event.schemaVersion, '1.0.0')
  assert.match(event.eventId, uuid)
  assert.match(event.game.gameId, uuid)
  assert.equal(event.source.pluginName, 'Chugmania Webhooks')
  assert.ok(['turbo', 'next'].includes(event.source.game))
  assert.ok(Number.isInteger(event.sequence) && event.sequence >= 0)
  assert.ok(Number.isInteger(event.durationMs) && event.durationMs >= 0)
  assert.match(
    event.occurredAt,
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/
  )

  if (event.type === 'start') {
    assert.equal(event.players.length, event.game.totalPlayers)
    event.players.forEach((player, index) => assertPlayer(player, index))
    assert.ok('map' in event)
    assert.ok(event.mode)
    if (event.map !== null) {
      for (const field of ['name', 'uid', 'author', 'environment', 'type']) {
        assert.equal(typeof event.map[field], 'string')
      }
      assert.ok(event.map.medalTimesMs)
      for (const medal of ['author', 'gold', 'silver', 'bronze']) {
        assert.ok(Number.isInteger(event.map.medalTimesMs[medal]))
        assert.ok(event.map.medalTimesMs[medal] >= 0)
      }
      assert.equal(typeof event.map.isLaps, 'boolean')
      assert.ok(Number.isInteger(event.map.totalLaps))
      assert.ok(event.map.totalLaps >= 0)
      assert.ok(Number.isInteger(event.map.checkpointsPerLap))
      assert.ok(event.map.checkpointsPerLap >= 0)
    }
    assert.ok(
      [
        'campaign',
        'arcade',
        'hot-seat',
        'split-screen',
        'secret',
        'solo',
        'unknown',
      ].includes(event.mode.name)
    )
    assert.notEqual(event.mode.type, 'script')
    if (event.mode.name === 'secret') assert.ok(event.mode.type)
  } else if (event.type === 'end') {
    assert.ok(
      ['completed', 'restarted', 'aborted', 'unknown'].includes(event.endReason)
    )
  } else {
    assertPlayer(event.player, 0)
    if (event.type !== 'first_throttle') assert.ok(event.checkpoint)
  }
}

console.log(`Validated ${events.length} webhook event fixtures.`)
