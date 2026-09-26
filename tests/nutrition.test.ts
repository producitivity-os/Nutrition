import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");

test("Nutrition preserves water and shows food completed from workflows", () => {
  const app = read("../src/App.tsx");
  const api = read("../src/api.ts");
  const native = read("../src-tauri/src/lib.rs");
  const config = JSON.parse(read("../src-tauri/tauri.conf.json")) as { productName: string; identifier: string; app: { windows: Array<{ title: string }> } };
  const migration = read("../../../crates/database/migrations/202609150001_create_nutrition_food_log.sql");
  assert.equal(config.productName, "Nutrition");
  assert.equal(config.identifier, "com.productivity-os.nutrition");
  assert.equal(config.app.windows[0].title, "Nutrition");
  assert.match(app, /const STEP = 250/);
  assert.match(app, /health-bottles/);
  assert.match(app, /nutrition-food-log/);
  assert.match(app, /Ate \{entry\.quantity\} \{entry\.mealName\}/);
  assert.match(api, /productivity-os\.health\.water-v1/);
  assert.match(api, /get_nutrition_water_day/);
  assert.match(api, /list_nutrition_food/);
  assert.match(native, /save_nutrition_water/);
  assert.match(native, /save_nutrition_food/);
  assert.match(native, /nutrition:food-changed/);
  assert.match(migration, /CREATE TABLE nutrition_food_entries/);
});
