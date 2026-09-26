import { invoke } from "@tauri-apps/api/core";

export type NutritionWaterDay = {
  localDate: string;
  targetMilliliters: number;
  intakeMilliliters: number;
  updatedAt: number;
};

export type NutritionFoodEntry = {
  id: string;
  localDate: string;
  mealName: string;
  quantity: number;
  workflowId: string;
  nodeId: string;
  loggedAt: number;
};

const isTauri = "__TAURI_INTERNALS__" in window || "__TAURI__" in window;
const legacyWaterKey = "productivity-os.health.water-v1";
const foodKey = "productivity-os.nutrition.food-v1";

export function localDay(date = new Date()): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function browserWater(date: string): NutritionWaterDay {
  try {
    const values = JSON.parse(localStorage.getItem(legacyWaterKey) ?? "{}") as Record<string, NutritionWaterDay>;
    return values[date] ?? { localDate: date, targetMilliliters: 2_000, intakeMilliliters: 0, updatedAt: Date.now() };
  } catch {
    return { localDate: date, targetMilliliters: 2_000, intakeMilliliters: 0, updatedAt: Date.now() };
  }
}

function browserFood(date: string): NutritionFoodEntry[] {
  try {
    const values = JSON.parse(localStorage.getItem(foodKey) ?? "[]") as NutritionFoodEntry[];
    return values.filter((entry) => entry.localDate === date).sort((a, b) => b.loggedAt - a.loggedAt);
  } catch {
    return [];
  }
}

export const nutritionApi = {
  async water(date = localDay()): Promise<NutritionWaterDay> {
    return isTauri ? invoke("get_nutrition_water_day", { localDate: date }) : browserWater(date);
  },
  async saveWater(value: NutritionWaterDay): Promise<NutritionWaterDay> {
    if (isTauri) return invoke("save_nutrition_water", { input: value });
    let values: Record<string, NutritionWaterDay> = {};
    try { values = JSON.parse(localStorage.getItem(legacyWaterKey) ?? "{}") as Record<string, NutritionWaterDay>; }
    catch { values = {}; }
    const saved = { ...value, updatedAt: Date.now() };
    values[value.localDate] = saved;
    localStorage.setItem(legacyWaterKey, JSON.stringify(values));
    window.dispatchEvent(new CustomEvent("nutrition:water-changed", { detail: saved }));
    return saved;
  },
  async food(date = localDay()): Promise<NutritionFoodEntry[]> {
    return isTauri ? invoke("list_nutrition_food", { localDate: date }) : browserFood(date);
  },
  async saveFood(value: NutritionFoodEntry): Promise<NutritionFoodEntry> {
    if (isTauri) return invoke("save_nutrition_food", { input: value });
    let values: NutritionFoodEntry[] = [];
    try { values = JSON.parse(localStorage.getItem(foodKey) ?? "[]") as NutritionFoodEntry[]; }
    catch { values = []; }
    values = [...values.filter((entry) => entry.id !== value.id), value];
    localStorage.setItem(foodKey, JSON.stringify(values));
    window.dispatchEvent(new CustomEvent("nutrition:food-changed", { detail: value }));
    return value;
  },
};
