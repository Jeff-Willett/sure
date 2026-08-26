import assert from "node:assert/strict"
import test from "node:test"

import {
  activeTagFragment,
  parseTagNames,
} from "../../../app/javascript/utils/tag_input.mjs"

test("parses comma-separated tag names and removes case-insensitive duplicates", () => {
  assert.deepEqual(
    parseTagNames("Apartment Setup, discretionary, apartment setup,  "),
    ["Apartment Setup", "discretionary"],
  )
})

test("returns the active fragment after the last comma", () => {
  assert.equal(activeTagFragment("Apartment Setup, disc"), "disc")
  assert.equal(activeTagFragment("Shopping"), "Shopping")
})
