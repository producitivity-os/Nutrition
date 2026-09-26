use app_core::{HealthWaterDay, NutritionFoodEntry, SaveHealthWaterInput, SaveNutritionFoodInput};
use data_client::DataClient;
use tauri::{AppHandle, Emitter, State};

struct AppState {
    client: Option<DataClient>,
    config_error: Option<String>,
}

impl AppState {
    fn client(&self) -> Result<DataClient, String> {
        self.client.clone().ok_or_else(|| {
            self.config_error
                .clone()
                .unwrap_or_else(|| "data service is unavailable".into())
        })
    }
}

#[tauri::command]
async fn get_nutrition_water_day(
    local_date: String,
    state: State<'_, AppState>,
) -> Result<HealthWaterDay, String> {
    state
        .client()?
        .health_water_day(local_date)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn save_nutrition_water(
    input: SaveHealthWaterInput,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<HealthWaterDay, String> {
    let saved = state
        .client()?
        .save_health_water(input)
        .await
        .map_err(|error| error.to_string())?;
    let _ = app.emit("nutrition:water-changed", &saved);
    Ok(saved)
}

#[tauri::command]
async fn list_nutrition_food(
    local_date: String,
    state: State<'_, AppState>,
) -> Result<Vec<NutritionFoodEntry>, String> {
    state
        .client()?
        .list_nutrition_food(local_date)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn save_nutrition_food(
    input: SaveNutritionFoodInput,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<NutritionFoodEntry, String> {
    let saved = state
        .client()?
        .save_nutrition_food(input)
        .await
        .map_err(|error| error.to_string())?;
    let _ = app.emit("nutrition:food-changed", &saved);
    Ok(saved)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let (client, config_error) = match app_config::ProductivityConfig::load() {
        Ok(config) => {
            let settings = config.service_settings();
            (
                Some(DataClient::new(
                    &settings.socket_path,
                    settings.max_request_bytes,
                )),
                None,
            )
        }
        Err(error) => (None, Some(error.to_string())),
    };
    tauri::Builder::default()
        .manage(AppState {
            client,
            config_error,
        })
        .invoke_handler(tauri::generate_handler![
            get_nutrition_water_day,
            save_nutrition_water,
            list_nutrition_food,
            save_nutrition_food,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Nutrition");
}
