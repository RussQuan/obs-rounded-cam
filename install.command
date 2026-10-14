#!/bin/bash
# OBS 圓角視訊安裝程式：新增一個場景集合「圓角視訊」，不會修改你原本的場景。
# 只用 macOS 內建工具（bash + osascript JavaScript），不需要 Python。
cd "$(dirname "$0")" || exit 1

pause() { read -n 1 -s -r -p "按任意鍵結束…"; echo; }

if pgrep -xiq obs; then
  echo "請先完全關閉 OBS（Cmd+Q）再執行一次。"
  pause; exit 1
fi

OBS_APP="/Applications/OBS.app"
if [ -d "$OBS_APP" ]; then
  ver=$(defaults read "$OBS_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
  if [ -n "$ver" ] && [ "${ver%%.*}" -lt 30 ]; then
    echo "偵測到 OBS $ver，本套件需要 OBS 30 以上，請先更新 OBS。"
    pause; exit 1
  fi
fi

osascript -l JavaScript - "$PWD" <<'JS'
ObjC.import('Foundation');

function run(argv) {
  const pkg = argv[0];
  const fm = $.NSFileManager.defaultManager;
  const env = $.NSProcessInfo.processInfo.environment;
  const HOME = ObjC.unwrap(env.objectForKey('HOME'));
  const OBS = HOME + '/Library/Application Support/obs-studio';
  const SCENES = OBS + '/basic/scenes';
  const ASSETS = OBS + '/rounded-cam';
  const OUT_NAME = 'Rounded_Cam';
  const COLL_NAME = '圓角視訊';

  const log = (s) => console.log(s);
  const exists = (p) => fm.fileExistsAtPath(p);
  const read = (p) => ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null));
  const write = (p, s) => $(s).writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null);
  const ls = (d) => (ObjC.unwrap(fm.contentsOfDirectoryAtPathError(d, null)) || []).map(ObjC.unwrap);
  const uuid = () => ObjC.unwrap($.NSUUID.UUID.UUIDString).toLowerCase();

  if (!exists(OBS)) {
    log('找不到 OBS 設定資料夾，請先開啟 OBS 一次再關閉，然後重新執行。');
    return;
  }

  // --- ini 讀寫（只處理 [section] key=value） ---
  function iniGet(text, section, key) {
    let cur = null;
    for (const line of (text || '').split('\n')) {
      const m = line.match(/^\[(.+)\]\s*$/);
      if (m) { cur = m[1]; continue; }
      if (cur === section && line.startsWith(key + '=')) return line.slice(key.length + 1).trim();
    }
    return null;
  }
  function iniSet(text, section, key, value) {
    const lines = text.split('\n');
    let cur = null, secEnd = -1;
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(/^\[(.+)\]\s*$/);
      if (m) { cur = m[1]; if (cur === section) secEnd = i + 1; continue; }
      if (cur === section) {
        if (lines[i].startsWith(key + '=')) { lines[i] = key + '=' + value; return lines.join('\n'); }
        if (lines[i].trim() !== '') secEnd = i + 1;
      }
    }
    if (secEnd < 0) return text.replace(/\n*$/, '\n') + '\n[' + section + ']\n' + key + '=' + value + '\n';
    lines.splice(secEnd, 0, key + '=' + value);
    return lines.join('\n');
  }

  // OBS 31 起把 [Basic] 移到 user.ini，舊版在 global.ini
  const iniPath = [OBS + '/user.ini', OBS + '/global.ini']
    .find((p) => exists(p) && iniGet(read(p), 'Basic', 'SceneCollectionFile') !== null)
    || (exists(OBS + '/user.ini') ? OBS + '/user.ini' : OBS + '/global.ini');
  const ini = read(iniPath) || '';

  // --- 畫布解析度：從目前使用的設定檔讀取 ---
  let canvas = [1920, 1080];
  const profileDir = iniGet(ini, 'Basic', 'ProfileDir');
  if (profileDir) {
    const basic = read(OBS + '/basic/profiles/' + profileDir + '/basic.ini');
    const cx = parseInt(iniGet(basic, 'Video', 'BaseCX'), 10);
    const cy = parseInt(iniGet(basic, 'Video', 'BaseCY'), 10);
    if (cx > 0 && cy > 0) canvas = [cx, cy];
  }

  // --- 從現有場景集合沿用鏡頭與螢幕（找不到就留空，讓使用者自己選） ---
  const CAM_IDS = ['macos-avcapture', 'macos-avcapture-fast', 'av_capture_input', 'av_capture_input_v2'];
  let camDev = null, displayUuid = null;
  const curFile = iniGet(ini, 'Basic', 'SceneCollectionFile');
  const files = ls(SCENES).filter((f) => f.endsWith('.json') && f !== OUT_NAME + '.json');
  files.sort((a, b) => (b === curFile + '.json') - (a === curFile + '.json')); // 目前的集合優先
  for (const f of files) {
    let data;
    try { data = JSON.parse(read(SCENES + '/' + f)); } catch (e) { continue; }
    for (const s of data.sources || []) {
      const st = s.settings || {};
      if (!camDev && CAM_IDS.includes(s.id) && st.device) camDev = { device: st.device, device_name: st.device_name || '' };
      if (!displayUuid && s.id === 'screen_capture' && st.display_uuid) displayUuid = st.display_uuid;
    }
    if (camDev && displayUuid) break;
  }

  // --- 複製圖片 ---
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(ASSETS, true, $(), null);
  for (const f of ['cam_mask.png', 'cam_frame.png']) {
    const src = pkg + '/assets/' + f, dst = ASSETS + '/' + f;
    if (!exists(src)) { log('缺少 assets/' + f + '，請重新下載完整套件。'); return; }
    fm.removeItemAtPathError(dst, null);
    fm.copyItemAtPathToPathError(src, dst, null);
  }

  // --- 版面（與 make_assets.py 一致；以 1800 高的畫布設計，再依比例縮放） ---
  const W = 480, H = 436, B = 6, P = 30, MARGIN = 30;
  const FW = W + 2 * B + 2 * P, FH = H + 2 * B + 2 * P;
  const CAM_W = H * 16 / 9;
  const k = canvas[1] / 1800;

  function src(name, id, settings, extra) {
    return Object.assign({
      name, uuid: uuid(), id, versioned_id: id, settings, mixers: 0, sync: 0, flags: 0,
      volume: 1.0, balance: 0.5, enabled: true, muted: false, hotkeys: {},
      deinterlace_mode: 0, deinterlace_field_order: 0, monitoring_type: 0, private_settings: {},
    }, extra || {});
  }
  function item(s, id, pos, opts) {
    opts = opts || {};
    return {
      name: s.name, source_uuid: s.uuid, visible: true, locked: false, rot: 0.0,
      pos: { x: pos[0], y: pos[1] }, scale: { x: opts.scale || 1.0, y: opts.scale || 1.0 },
      align: 5, bounds_type: opts.bounds ? 2 : 0, bounds_align: 0, bounds_crop: false,
      bounds: { x: opts.bounds ? opts.bounds[0] : 0, y: opts.bounds ? opts.bounds[1] : 0 },
      crop_left: 0, crop_top: 0, crop_right: 0, crop_bottom: 0, id,
      group_item_backup: false, scale_filter: 'disable', blend_method: 'default', blend_type: 'normal',
      show_transition: { duration: 0 }, hide_transition: { duration: 0 }, private_settings: {},
    };
  }

  const mask = src('圓角遮罩', 'mask_filter', {
    image_path: ASSETS + '/cam_mask.png', type: 'mask_color_filter.effect',
    color: 4294967295, opacity: 1.0, stretch: false,
  }, { versioned_id: 'mask_filter_v2' });
  const cam = src('圓角鏡頭', 'macos-avcapture',
    Object.assign({ preset: 'AVCaptureSessionPreset1280x720' }, camDev || {}), { filters: [mask] });
  const frame = src('鏡頭白框', 'image_source', { file: ASSETS + '/cam_frame.png' });
  const screenSettings = { type: 0, show_cursor: true, hide_obs: false };
  if (displayUuid) screenSettings.display_uuid = displayUuid;
  const screen = src('螢幕擷取', 'screen_capture', screenSettings);
  const mic = src('麥克風', 'coreaudio_input_capture', { device_id: 'default' }, { mixers: 255 });

  const camBox = src('鏡頭框組', 'scene', {
    id_counter: 2, custom_size: true, cx: FW, cy: FH,
    items: [item(frame, 1, [0, 0]), item(cam, 2, [P + B - (CAM_W - W) / 2, P + B], { bounds: [CAM_W, H] })],
  });
  const main = src('螢幕 + 圓角鏡頭', 'scene', {
    id_counter: 3, custom_size: false,
    items: [
      item(screen, 1, [0, 0], { bounds: canvas }),
      item(camBox, 2, [canvas[0] - (FW + MARGIN) * k, canvas[1] - (FH + MARGIN) * k], { scale: k }),
      item(mic, 3, [0, 0]),
    ],
  });

  const coll = {
    name: COLL_NAME, current_scene: main.name, current_program_scene: main.name,
    scene_order: [{ name: main.name }, { name: camBox.name }],
    sources: [main, camBox, cam, frame, screen, mic], groups: [],
    quick_transitions: [], transitions: [], saved_projectors: [],
    current_transition: 'Fade', transition_duration: 300, preview_locked: false,
    scaling_enabled: false, scaling_level: 0, scaling_off_x: 0.0, scaling_off_y: 0.0,
    modules: {}, resolution: { x: canvas[0], y: canvas[1] },
  };
  write(SCENES + '/' + OUT_NAME + '.json', JSON.stringify(coll, null, 2));

  // --- 讓 OBS 下次啟動直接進入「圓角視訊」（避免在 OBS 內切換集合時觸發 macOS 視訊效果的閃退） ---
  const prevName = iniGet(ini, 'Basic', 'SceneCollection');
  const prevFile = iniGet(ini, 'Basic', 'SceneCollectionFile');
  if (prevFile && prevFile !== OUT_NAME) {
    write(ASSETS + '/previous.json', JSON.stringify({ iniPath, name: prevName, file: prevFile }));
  }
  let newIni = iniSet(ini, 'Basic', 'SceneCollection', COLL_NAME);
  newIni = iniSet(newIni, 'Basic', 'SceneCollectionFile', OUT_NAME);
  write(iniPath, newIni);

  log('');
  log('✅ 安裝完成');
  log('   畫布：' + canvas[0] + '×' + canvas[1]);
  log('   鏡頭：' + (camDev ? (camDev.device_name || '沿用現有鏡頭') : '未偵測到，請在 OBS 裡手動選擇'));
  log('   螢幕：' + (displayUuid ? '沿用現有螢幕' : '未偵測到，請在 OBS 裡手動選擇'));
  log('');
  log('現在打開 OBS，會直接進入「圓角視訊」場景集合。');
}
JS
pause
