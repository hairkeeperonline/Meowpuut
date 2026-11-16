$p = 'E:\WTY.build\crop_e6_emoji.png'
if (Test-Path $p) { Write-Host "FOUND: $p"; Get-Item $p | Select FullName,Length }
else {
  Write-Host "NOT FOUND at $p"
  # search E:\ for WTY* dirs
  Get-ChildItem 'E:\' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'WTY|wtymap|build' } | ForEach-Object { Write-Host $_.FullName }
  # also try common locations
  foreach ($cand in @('E:\WTY','E:\WTY.build','E:\wtymap','E:\wtymap.build','E:\e','E:\WTY_Map')) {
    if (Test-Path $cand) { Write-Host "EXISTS: $cand"; Get-ChildItem $cand -Filter '*emoji*' -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select -First 5 FullName }
  }
}
