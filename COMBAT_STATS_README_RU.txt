TANKI 2.0 PROTOTYPE — COMBAT v16

Баланс хранится в одном общем файле:
  client/data/combat_stats.json

Его читает и Godot-клиент, и Python-сервер.
После изменения combat_stats.json сервер нужно перезапустить.

Текущие модификации:
  Wasp M2
  Viking M1
  Mamont M3
  Smoky M2
  Firebird M1
  Thunder M3

Модификаторы M0..M3 находятся в секции "modifiers".
Формулы сейчас такие:
  max_hp = base_hp * modifiers[M].hp
  damage / dps = base_damage / base_dps * modifiers[M].damage
  reload = base_reload * modifiers[M].reload
  Firebird fuel_max = fuel_capacity * modifiers[M].fuel

Текущий ориентировочный баланс:
  Wasp M2   ~924 HP
  Viking M1 ~1150 HP
  Mamont M3 ~2052 HP

  Smoky M2   ~194 damage, reload ~0.87 s
  Thunder M3 ~636 damage, reload ~2.33 s, splash radius 7.5 m
  Firebird M1 ~122 DPS, fuel ~108, afterburn duration 4.2 s

Firebird:
  - расходует топливо только во время огня;
  - восстанавливает его после отпускания огня и небольшой задержки;
  - попадание поджигает противника;
  - afterburn damage линейно ослабевает до нуля;
  - повторное попадание обновляет время горения.

Для будущих M0/M1/M2/M3 можно менять default_mod в hulls/weapons или начать
передавать другой hull_mod/turret_mod из меню. Сервер уже принимает значения 0..3.
