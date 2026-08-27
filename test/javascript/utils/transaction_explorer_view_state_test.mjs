import assert from "node:assert/strict"
import test from "node:test"

import {
  TRANSACTION_EXPLORER_VIEW_STATE_KEY,
  parseExplorerViewState,
  serializeExplorerViewState,
} from "../../../app/javascript/utils/transaction_explorer_view_state.mjs"

test("defaults to the scrolling layout with rollups closed", () => {
  assert.equal(
    TRANSACTION_EXPLORER_VIEW_STATE_KEY,
    "myfin:transaction-explorer:view-state:v1",
  )
  assert.deepEqual(parseExplorerViewState(null), {
    layout: "fitDataStretch",
    rollupsOpen: false,
    columns: null,
  })
})

test("round trips the chosen layout, rollup state, and column layout", () => {
  const state = {
    layout: "fitColumns",
    rollupsOpen: true,
    columns: [
      { field: "entity", width: 72, visible: true },
      { field: "description", width: 420, visible: false },
    ],
  }

  assert.deepEqual(parseExplorerViewState(serializeExplorerViewState(state)), state)
})

test("rejects malformed or unsafe stored state", () => {
  assert.deepEqual(parseExplorerViewState("not json"), {
    layout: "fitDataStretch",
    rollupsOpen: false,
    columns: null,
  })
  assert.deepEqual(
    parseExplorerViewState(
      JSON.stringify({
        layout: "unknown",
        rollupsOpen: "yes",
        columns: [{ field: "amount", width: -1, visible: true }],
      }),
    ),
    {
      layout: "fitDataStretch",
      rollupsOpen: false,
      columns: null,
    },
  )
})
