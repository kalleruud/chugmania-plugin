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
assert.match(start.players[0].localId, /^\d+$/)
assert.match(start.players[0].accountId, uuid)
assert.equal(lap.checkpoint.checkpointLapIndex, 0)
assert.equal(
  finish.checkpoint.checkpointLapIndex,
  start.map.checkpointsPerLap + 1
)

for (const event of events) {
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
    assert.ok(event.map && event.mode)
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
    if (event.mode.name === 'secret') assert.ok(event.mode.type)
  } else if (event.type === 'end') {
    assert.ok(
      ['completed', 'restarted', 'aborted', 'unknown'].includes(event.endReason)
    )
  } else {
    assert.ok(event.player)
    if (event.type !== 'first_throttle') assert.ok(event.checkpoint)
  }
}

console.log(`Validated ${events.length} webhook event fixtures.`)
