#!/bin/bash
# 移除 OBS 圓角視訊：刪除「圓角視訊」場景集合與圖片，並把 OBS 切回原本的場景集合。
cd "$(dirname "$0")" || exit 1

pause() { read -n 1 -s -r -p "按任意鍵結束…"; echo; }

if pgrep -xiq obs; then
  echo "請先完全關閉 OBS（Cmd+Q）再執行一次。"
  pause; exit 1
fi

osascript -l JavaScript - <<'JS'
ObjC.import('Foundation');

function run() {
  const fm = $.NSFileManager.defaultManager;
  const HOME = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('HOME'));
  const OBS = HOME + '/Library/Application Support/obs-studio';
  const SCENES = OBS + '/basic/scenes';
  const ASSETS = OBS + '/rounded-cam';
  const OUT_NAME = 'Rounded_Cam';

  const exists = (p) => fm.fileExistsAtPath(p);
  const read = (p) => ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null));
  const write = (p, s) => $(s).writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null);
  const ls = (d) => (ObjC.unwrap(fm.contentsOfDirectoryAtPathError(d, null)) || []).map(ObjC.unwrap);

  function iniSetBasic(text, key, value) {
    const lines = text.split('\n');
    let cur = null;
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(/^\[(.+)\]\s*$/);
      if (m) { cur = m[1]; continue; }
      if (cur === 'Basic' && lines[i].startsWith(key + '=')) lines[i] = key + '=' + value;
    }
    return lines.join('\n');
  }

  // 找出要切回的場景集合：安裝時記下的那個，否則任選另一個
  let prev = null;
  try { prev = JSON.parse(read(ASSETS + '/previous.json')); } catch (e) {}
  if (prev && !exists(SCENES + '/' + prev.file + '.json')) prev = null;
  if (!prev) {
    const other = ls(SCENES).find((f) => f.endsWith('.json') && f !== OUT_NAME + '.json');
    if (other) {
      let name = other.replace(/\.json$/, '');
      try { name = JSON.parse(read(SCENES + '/' + other)).name || name; } catch (e) {}
      prev = { name, file: other.replace(/\.json$/, '') };
    }
  }

  for (const iniPath of [OBS + '/user.ini', OBS + '/global.ini']) {
    const ini = read(iniPath);
    if (!ini || !ini.includes('SceneCollectionFile=' + OUT_NAME)) continue;
    if (prev) {
      write(iniPath, iniSetBasic(iniSetBasic(ini, 'SceneCollection', prev.name), 'SceneCollectionFile', prev.file));
    }
  }

  for (const f of [OUT_NAME + '.json', OUT_NAME + '.json.bak']) fm.removeItemAtPathError(SCENES + '/' + f, null);
  fm.removeItemAtPathError(ASSETS, null);

  console.log('✅ 已移除「圓角視訊」' + (prev ? '，OBS 下次會開啟「' + prev.name + '」' : ''));
}
JS
pause
