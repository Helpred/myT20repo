# Arena v3 — редактирование в Godot

Основная рабочая сцена:

`client/scenes/maps/arena_editable.tscn`

Игра теперь загружает **именно эту сцену**. `arena_original.gd` остался только как старый/справочный вариант и больше не управляет картой при запуске.

## Структура

- `Environment` — небо, ambient, fog. Выдели узел и открой ресурс `Environment` в Inspector.
- `Geometry/OriginalArena_DO_NOT_MOVE` — исходная геометрия Arena из A3D. В этой editor-версии удалены baked vertex-lighting и beam meshes.
- `Collision/PhysicsMesh` — исходная физическая геометрия. Она скрыта. Можно временно включить глазик в редакторе, чтобы посмотреть collision layout.
- `Lighting/OriginalLampRig` — импортированный исходный набор ламп. Для него включены Editable Children. Можно раскрывать дерево и двигать/крутить `SpotLight3D` / `OmniLight3D`, менять Energy/Color/Range/Angle.
- `Props` — сюда безопасно добавлять свои ящики, бочки, декорации и прочие новые объекты.
- `ChemicalPools` — каждая лужа отдельным узлом. `Water` отвечает за геометрию/материал, `Glow` — за зелёный OmniLight.
- `Effects` — пустая папка под частицы, дым, пар и т.п.
- `SpawnPoints` — три `Marker3D`. Их можно двигать/вращать; игра автоматически использует новые позиции после Ctrl+S.

## Самое важное правило

Не двигай `Geometry/OriginalArena_DO_NOT_MOVE`, если не двигаешь соответствующую collision-геометрию. Визуал и `arena_physics.obj` — разные ресурсы.

Для своих новых Props делай объект примерно так:

```
Props
└── Crate01 (StaticBody3D)
    ├── MeshInstance3D
    └── CollisionShape3D
```

Так визуал и физика всегда будут перемещаться вместе.

## Освещение

1. Открой `Lighting/OriginalLampRig`.
2. Если Godot вдруг не позволяет выбирать его дочерние узлы: ПКМ по `OriginalLampRig` → `Editable Children`.
3. Выбери нужный `SpotLight3D`.
4. Основные поля:
   - `Light > Energy`
   - `Light > Color`
   - `Spot > Range`
   - `Spot > Angle`
   - `Shadow > Enabled`
5. Поворачивай сам узел света gizmo-манипулятором в 3D viewport.

В `lights_editor.dae` заранее удалены слой-дубликат `Shadows` и `Direct01`, поэтому отдельного верхнего солнца в editor-сцене нет.

## Baked light / старые лучи

`arena_visual_editor.gltf` — специальная редакторская версия:

- `COLOR_0`, в котором был перенесён baked lightmap, удалён;
- primitive `bims_rgba` с геометрическими лучами света удалён.

То есть свет теперь можно строить обычными Godot lights без старой запечённой подсветки поверх них.

## Химические лужи

Например `ChemicalPools/Pool_01`:

- двигай/вращай **сам Pool_01**, чтобы вода и источник света двигались вместе;
- размер меняй через `Water > Scale`;
- яркость свечения — `Glow > Light > Energy`;
- радиус — `Glow > Omni > Range`;
- общий материал воды — `res://shaders/chemical_puddle.gdshader`.

Сейчас четыре лужи используют один материал. Если захочешь отдельный цвет для конкретной лужи, сделай материал Unique перед правкой.

## Spawn points

`Spawn_0`, `Spawn_1`, `Spawn_2` соответствуют Wasp, Viking, Mamont. Просто передвинь Marker3D и сохрани сцену — менять `main.gd` больше не нужно.

## Что лучше оставить технической части

Безопаснее не менять вручную:

- `arena_visual_editor.gltf`
- `arena_visual.bin`
- `arena_physics.obj`
- сетевые скрипты
- физику танка

Если потребуется передвинуть/разбить именно исходную крупную геометрию Arena с правильной collision-геометрией, лучше сначала изменить конвертер, чтобы визуал и collision оставались синхронны.
