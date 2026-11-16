Get-ChildItem -Path 'E:\WTY' -Filter '*scr_ks*' -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length
