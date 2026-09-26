import * as React from "react";
import { Droplets, Minus, Plus, Utensils } from "lucide-react";
import { AppHeader } from "@productivity-os/shared-ui/components/app-header";
import { Button } from "@productivity-os/shared-ui/components/ui/button";
import { DataServiceRecoveryDialog, dataServiceIssueFrom } from "@productivity-os/shared-ui/components/data-service-recovery";
import { nutritionApi, type NutritionFoodEntry, type NutritionWaterDay } from "./api";

const STEP = 250;

function WaterBottle({ capacity, filled }: { capacity: number; filled: number }) {
  const ratio = Math.max(0, Math.min(1, filled / capacity));
  return <div className="health-bottle" aria-label={`${Math.round(filled)} of ${capacity} millilitres`}>
    <span className="health-bottle-neck" />
    <span className="health-bottle-water" style={{ height: `${ratio * 100}%` }} />
    <Droplets aria-hidden="true" />
  </div>;
}

export function App() {
  const [day, setDay] = React.useState<NutritionWaterDay | null>(null);
  const [food, setFood] = React.useState<NutritionFoodEntry[]>([]);
  const [error, setError] = React.useState<ReturnType<typeof dataServiceIssueFrom> | null>(null);
  const [saving, setSaving] = React.useState(false);
  const load = React.useCallback(() => {
    void Promise.all([nutritionApi.water(), nutritionApi.food()])
      .then(([water, meals]) => { setDay(water); setFood(meals); setError(null); })
      .catch((reason) => setError(dataServiceIssueFrom(reason)));
  }, []);
  React.useEffect(() => {
    load();
    const onVisible = () => { if (document.visibilityState === "visible") load(); };
    window.addEventListener("focus", load);
    window.addEventListener("nutrition:water-changed", load);
    window.addEventListener("nutrition:food-changed", load);
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      window.removeEventListener("focus", load);
      window.removeEventListener("nutrition:water-changed", load);
      window.removeEventListener("nutrition:food-changed", load);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [load]);

  const save = React.useCallback((next: NutritionWaterDay) => {
    if (saving) return;
    setSaving(true);
    void nutritionApi.saveWater(next).then(setDay).catch((reason) => setError(dataServiceIssueFrom(reason))).finally(() => setSaving(false));
  }, [saving]);

  const target = day?.targetMilliliters ?? 2_000;
  const intake = day?.intakeMilliliters ?? 0;
  const bottles = Array.from({ length: Math.ceil(target / 1_000) }, (_, index) => {
    const capacity = Math.min(1_000, target - index * 1_000);
    return { capacity, filled: Math.min(capacity, Math.max(0, intake - index * 1_000)) };
  });

  return <div className="health-app nutrition-app">
    <AppHeader><div className="health-header" data-tauri-drag-region><Droplets /><span>Nutrition</span></div></AppHeader>
    <main>
      <p className="health-eyebrow">Today</p>
      <h1>Water</h1>
      <p className="health-total">{(intake / 1_000).toFixed(2)} <span>/ {(target / 1_000).toFixed(2)} L</span></p>
      <div className="health-bottles">{bottles.map((bottle, index) => <WaterBottle key={index} {...bottle} />)}</div>
      <div className="health-actions">
        <Button variant="outline" size="icon" disabled={!day || saving || intake === 0} onClick={() => day && save({ ...day, intakeMilliliters: Math.max(0, intake - STEP) })}><Minus /><span className="sr-only">Remove 0.25 litres</span></Button>
        <Button disabled={!day || saving} onClick={() => day && save({ ...day, intakeMilliliters: intake + STEP })}><Plus /> Add 0.25 L</Button>
      </div>
      <label className="health-target">Daily target
        <input type="range" min={250} max={10_000} step={250} value={target} onChange={(event) => day && save({ ...day, targetMilliliters: Number(event.currentTarget.value) })} />
        <span>{(target / 1_000).toFixed(2)} L</span>
      </label>
      <section className="nutrition-food-log" aria-labelledby="nutrition-food-title">
        <header><span><Utensils aria-hidden="true" /></span><div><p className="health-eyebrow">Today</p><h2 id="nutrition-food-title">Food</h2></div></header>
        {food.length ? <ol>{food.map((entry) => <li key={entry.id}><span>Ate {entry.quantity} {entry.mealName}</span><time dateTime={new Date(entry.loggedAt).toISOString()}>{new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(entry.loggedAt)}</time></li>)}</ol> : <p className="nutrition-food-empty">Food completed from a workflow will appear here.</p>}
      </section>
    </main>
    <DataServiceRecoveryDialog issue={error} onRetry={() => { setError(null); load(); }} onClose={() => window.close()} />
  </div>;
}
