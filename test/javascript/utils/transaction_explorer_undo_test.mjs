import assert from "node:assert/strict"
import test from "node:test"

import { captureEditResult } from "../../../app/javascript/utils/transaction_explorer_undo.mjs"

function streamFor(result) {
  return {
    querySelector() {
      return {
        content: {
          querySelector() {
            return result
          },
        },
      }
    },
  }
}

function editResult(changeId) {
  const result = { dataset: { changeId } }
  result.cloneNode = () => ({ dataset: { ...result.dataset } })
  return result
}

test("captures each rapid edit result before the shared result slot changes", () => {
  const first = captureEditResult(streamFor(editResult("change-1")))
  const second = captureEditResult(streamFor(editResult("change-2")))

  assert.equal(first.dataset.changeId, "change-1")
  assert.equal(second.dataset.changeId, "change-2")
  assert.notEqual(first, second)
})
