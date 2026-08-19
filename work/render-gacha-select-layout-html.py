from __future__ import annotations

import argparse
import html
import json
import shutil
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JSON = ROOT / "server" / "data" / "game" / "gacha.json"
DEFAULT_XML = ROOT / "work" / "million_cn" / "apktool" / "assets" / "bundle" / "local_gachaselect.xml"
DEFAULT_LAYOUT = ROOT / "work" / "million_cn" / "apktool" / "assets" / "bundle" / "layout_gacha_select.xml"
BASE_APK = ROOT / "base" / "com.square_enix.million_cn-1.0.0.100.0712.M330.apk"
DEFAULT_IMAGE_DIR = ROOT / "work" / "gacha-image-preview" / "decoded"
DEFAULT_OUT_DIR = ROOT / "work" / "gacha-layout-html-check"
DEFAULT_FRAME_WIDTH = 400
SLOT_ROLES = ["ticket", "comp_sheet", "friendship", "paid_mc"]
SLOT_LABELS = {
    "ticket": "扭蛋券",
    "comp_sheet": "收集奖励",
    "friendship": "友情扭蛋",
    "paid_mc": "付费扭蛋",
}


def parse_int(value: object, fallback: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def image_size(image_dir: Path, name: str) -> tuple[int, int] | None:
    path = image_dir / f"{name}.png"
    if not path.exists():
        return None
    with Image.open(path) as image:
        return image.size


def display_size(size: tuple[int, int] | None, scale: float) -> tuple[int, int]:
    if size is None:
        return (0, 0)
    return (max(1, round(size[0] * scale)), max(1, round(size[1] * scale)))


def resolve_product_tokens(value: object, product: dict[str, object]) -> object:
    if not isinstance(value, str):
        return value
    return value.replace("{cost}", str(parse_int(product.get("cost"), 0))).replace(
        "{currencyLabel}", str(product.get("currencyLabel") or "")
    )


def read_json_contents(json_path: Path, page_name: str) -> tuple[int, list[dict[str, object]]]:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    default_page = data.get("defaultPage", "main")
    page = (data.get("pages") or {}).get(page_name or default_page) or {}
    products = {
        parse_int(product.get("productId")): product
        for product in data.get("products") or []
        if isinstance(product, dict)
    }
    contents: list[dict[str, object]] = []
    for source_content in page.get("contents") or []:
        if not isinstance(source_content, dict):
            continue
        content = dict(source_content)
        product = products.get(parse_int(content.get("productId")))
        if product:
            content["behavior"] = content.get("behavior") or product.get("behavior")
            content["message"] = resolve_product_tokens(content.get("message"), product)
            content["textMessages"] = [
                {
                    **message,
                    "text": resolve_product_tokens(message.get("text"), product),
                }
                for message in content.get("textMessages") or []
                if isinstance(message, dict)
            ]
        contents.append(content)
    return parse_int(page.get("scrollHeight"), 0), contents


def text_messages_from_json(content: dict[str, object]) -> str:
    messages = content.get("textMessages") or []
    if not isinstance(messages, list):
        return ""
    return "".join(str(message.get("text", "")) for message in messages if isinstance(message, dict))


def text_messages_from_xml(content: ET.Element) -> str:
    messages = []
    for message in content.findall("./textdata/message"):
        messages.append(message.findtext("text", default=""))
    return "".join(messages)


def read_bundled_xml(path: Path, apk_entry: str) -> ET.Element:
    if path.exists():
        return ET.parse(path).getroot()
    if not BASE_APK.exists():
        raise SystemExit(f"missing {path} and base APK {BASE_APK}")
    with zipfile.ZipFile(BASE_APK) as apk:
        return ET.fromstring(apk.read(apk_entry))


def read_xml_contents(xml_path: Path) -> tuple[int, list[dict[str, object]]]:
    root = read_bundled_xml(xml_path, "assets/bundle/local_gachaselect.xml")
    xml_contents = root.find("./body/gacha_select/xml_contents")
    if xml_contents is None:
        raise SystemExit(f"missing gacha_select/xml_contents in {xml_path}")
    scroll_height = parse_int(xml_contents.findtext("scroll_height", "0"))
    contents: list[dict[str, object]] = []
    for content in xml_contents.findall("content"):
        contents.append(
            {
                "actionId": parse_int(content.findtext("action_id", "0")),
                "imagefile": content.findtext("imagefile"),
                "x": parse_int(content.findtext("x", "0")),
                "y": parse_int(content.findtext("y", "0")),
                "behavior": content.findtext("behavior"),
                "message": content.findtext("message"),
                "text": text_messages_from_xml(content),
            }
        )
    return scroll_height, contents


def read_layout_frame_width(layout_path: Path) -> int:
    root = read_bundled_xml(layout_path, "assets/bundle/layout_gacha_select.xml")
    viewer = root.find(".//xml_viewer[@name='viewer']")
    if viewer is None:
        return DEFAULT_FRAME_WIDTH
    return parse_int(viewer.get("frame_w"), DEFAULT_FRAME_WIDTH)


def infer_display_scale(contents: list[dict[str, object]], image_dir: Path, frame_width: int) -> float:
    image_contents = [content for content in contents if content.get("imagefile")]
    if not image_contents:
        return 1.0
    widest_width = 0
    widest_x = 0
    for content in image_contents:
        size = image_size(image_dir, str(content.get("imagefile") or ""))
        if size and size[0] > widest_width:
            widest_width = size[0]
            widest_x = parse_int(content.get("x"), 0)
    if widest_width <= 0:
        return 1.0
    # ponytail: local gacha XML uses 2x PNGs; if a future page mixes scales, replace this with per-asset scale.
    return max(0.1, min(1.0, (frame_width - widest_x) / widest_width))


def build_elements(
    contents: list[dict[str, object]], image_dir: Path, source: str, display_scale: float
) -> list[dict[str, object]]:
    elements: list[dict[str, object]] = []
    for index, content in enumerate(contents):
        imagefile = content.get("imagefile")
        x = parse_int(content.get("x"), 0)
        y = parse_int(content.get("y"), 0)
        action_id = parse_int(content.get("actionId"), 0)
        if imagefile:
            name = str(imagefile)
            size = image_size(image_dir, name)
            natural_width, natural_height = size or (0, 0)
            width, height = display_size(size, display_scale)
            elements.append(
                {
                    "source": source,
                    "kind": "image",
                    "index": index,
                    "actionId": action_id,
                    "name": name,
                    "x": x,
                    "y": y,
                    "width": width,
                    "height": height,
                    "naturalWidth": natural_width,
                    "naturalHeight": natural_height,
                    "missing": size is None,
                    "behavior": content.get("behavior"),
                    "message": content.get("message"),
                }
            )
        text = str(content.get("text") or text_messages_from_json(content))
        if text:
            # ponytail: text width is approximate; browser report uses actual DOM boxes.
            elements.append(
                {
                    "source": source,
                    "kind": "text",
                    "index": index,
                    "actionId": action_id,
                    "name": text,
                    "x": x,
                    "y": y,
                    "width": max(160, len(text) * 18),
                    "height": 28,
                    "missing": False,
                    "behavior": content.get("behavior"),
                    "message": content.get("message"),
                }
            )
    return elements


def slot_role(index: int) -> str:
    if index < len(SLOT_ROLES):
        return SLOT_ROLES[index]
    return f"slot_{index + 1}"


def read_image_candidates(image_dir: Path, display_scale: float) -> list[dict[str, object]]:
    candidates: list[dict[str, object]] = []
    for path in sorted(image_dir.glob("*.png")):
        with Image.open(path) as image:
            natural_width, natural_height = image.size
        width, height = display_size((natural_width, natural_height), display_scale)
        name = path.stem
        notes = []
        if name.startswith(("gac_", "ae_gacha_")):
            notes.append("xml-name")
        if name.startswith("gacha_free_blank") or name == "gacha_paid_banner":
            notes.append("rejected/generated")
        candidates.append(
            {
                "name": name,
                "src": f"assets/{path.name}",
                "width": width,
                "height": height,
                "naturalWidth": natural_width,
                "naturalHeight": natural_height,
                "notes": notes,
            }
        )
    return candidates


def read_xml_slots(
    contents: list[dict[str, object]], scroll_height: int, image_dir: Path, frame_width: int
) -> list[dict[str, object]]:
    image_contents = [content for content in contents if content.get("imagefile")]
    slots: list[dict[str, object]] = []
    for index, content in enumerate(image_contents):
        y = parse_int(content.get("y"), 0)
        next_y = parse_int(image_contents[index + 1].get("y"), scroll_height) if index + 1 < len(image_contents) else scroll_height
        image_name = str(content.get("imagefile") or "")
        size = image_size(image_dir, image_name)
        role = slot_role(index)
        slots.append(
            {
                "id": role,
                "label": SLOT_LABELS.get(role, role),
                "sourceImage": image_name,
                "x": 0,
                "contentX": parse_int(content.get("x"), 0),
                "y": y,
                "width": frame_width,
                "height": max(1, next_y - y),
                "imageWidth": size[0] if size else 0,
                "imageHeight": size[1] if size else 0,
            }
        )
    return slots


def build_locked_editor_placements(
    current_contents: list[dict[str, object]],
    reference_contents: list[dict[str, object]],
    image_dir: Path,
    source: str,
    display_scale: float,
) -> list[dict[str, object]]:
    placements: list[dict[str, object]] = []
    image_ordinal = -1
    current_role = slot_role(0)
    for index, reference in enumerate(reference_contents):
        content = dict(current_contents[index]) if index < len(current_contents) else dict(reference)
        if reference.get("imagefile"):
            image_ordinal += 1
            current_role = slot_role(image_ordinal)
        content["x"] = parse_int(reference.get("x"), 0)
        content["y"] = parse_int(reference.get("y"), 0)
        if content.get("imagefile"):
            placements.append(
                placement_from_content(
                    content,
                    index,
                    image_dir,
                    current_role,
                    source=source,
                    display_scale=display_scale,
                    image_ordinal=image_ordinal if image_ordinal >= 0 else None,
                )
            )
        if content.get("text") or text_messages_from_json(content):
            placements.append(
                placement_from_content(content, index, image_dir, current_role, source=source, display_scale=display_scale)
            )
    return placements


def placement_from_content(
    content: dict[str, object],
    index: int,
    image_dir: Path,
    role: str,
    *,
    source: str,
    display_scale: float,
    image_ordinal: int | None = None,
) -> dict[str, object]:
    x = parse_int(content.get("x"), 0)
    y = parse_int(content.get("y"), 0)
    action_id = parse_int(content.get("actionId"), 0)
    imagefile = content.get("imagefile")
    text = str(content.get("text") or text_messages_from_json(content))
    base = {
        "id": f"{source}-{index}-{image_ordinal if image_ordinal is not None else 'text'}",
        "slot": role,
        "order": index,
        "x": x,
        "y": y,
        "actionId": action_id,
        "se": content.get("se"),
        "message": content.get("message"),
        "behavior": content.get("behavior"),
    }
    if imagefile:
        name = str(imagefile)
        size = image_size(image_dir, name)
        natural_width, natural_height = size or (0, 0)
        width, height = display_size(size, display_scale)
        return {
            **base,
            "kind": "image",
            "name": name,
            "src": f"assets/{name}.png",
            "width": width,
            "height": height,
            "naturalWidth": natural_width,
            "naturalHeight": natural_height,
            "missing": size is None,
        }
    return {
        **base,
        "kind": "text",
        "name": text,
        "text": text,
        "textMessages": content.get("textMessages") or [],
        "width": max(160, len(text) * 18),
        "height": 30,
        "missing": False,
    }


def build_editor_placements(
    contents: list[dict[str, object]], image_dir: Path, source: str, display_scale: float
) -> list[dict[str, object]]:
    placements: list[dict[str, object]] = []
    image_ordinal = -1
    current_role = slot_role(0)
    for index, content in enumerate(contents):
        if content.get("imagefile"):
            image_ordinal += 1
            current_role = slot_role(image_ordinal)
            placements.append(
                placement_from_content(
                    content,
                    index,
                    image_dir,
                    current_role,
                    source=source,
                    display_scale=display_scale,
                    image_ordinal=image_ordinal,
                )
            )
        if content.get("text") or text_messages_from_json(content):
            placements.append(
                placement_from_content(content, index, image_dir, current_role, source=source, display_scale=display_scale)
            )
    return placements


def overlap(a: dict[str, object], b: dict[str, object]) -> dict[str, object] | None:
    ax1 = parse_int(a["x"])
    ay1 = parse_int(a["y"])
    ax2 = ax1 + parse_int(a["width"])
    ay2 = ay1 + parse_int(a["height"])
    bx1 = parse_int(b["x"])
    by1 = parse_int(b["y"])
    bx2 = bx1 + parse_int(b["width"])
    by2 = by1 + parse_int(b["height"])
    width = min(ax2, bx2) - max(ax1, bx1)
    height = min(ay2, by2) - max(ay1, by1)
    if width <= 0 or height <= 0:
        return None
    return {
        "a": a["name"],
        "b": b["name"],
        "width": width,
        "height": height,
        "area": width * height,
    }


def collect_static_issues(elements: list[dict[str, object]], scroll_height: int) -> dict[str, object]:
    image_elements = [element for element in elements if element["kind"] == "image"]
    overlaps = []
    for left_index, left in enumerate(image_elements):
        for right in image_elements[left_index + 1 :]:
            item = overlap(left, right)
            if item:
                overlaps.append(item)
    overflow = [
        {
            "name": element["name"],
            "bottom": parse_int(element["y"]) + parse_int(element["height"]),
            "scrollHeight": scroll_height,
        }
        for element in image_elements
        if scroll_height and parse_int(element["y"]) + parse_int(element["height"]) > scroll_height
    ]
    missing = [element["name"] for element in image_elements if element.get("missing")]
    return {"overlaps": overlaps, "overflow": overflow, "missing": missing}


def render_panel(title: str, scroll_height: int, elements: list[dict[str, object]]) -> str:
    item_html = []
    for element in elements:
        style = (
            f"left:{parse_int(element['x'])}px;"
            f"top:{parse_int(element['y'])}px;"
            f"width:{parse_int(element['width'])}px;"
            f"height:{parse_int(element['height'])}px;"
        )
        data_attrs = (
            f'data-kind="{html.escape(str(element["kind"]))}" '
            f'data-name="{html.escape(str(element["name"]))}" '
            f'data-x="{parse_int(element["x"])}" '
            f'data-y="{parse_int(element["y"])}" '
            f'data-width="{parse_int(element["width"])}" '
            f'data-height="{parse_int(element["height"])}"'
        )
        if element["kind"] == "image" and not element.get("missing"):
            src = f"assets/{element['name']}.png"
            body = f'<img src="{html.escape(src)}" alt="{html.escape(str(element["name"]))}">'
        else:
            body = html.escape(str(element["name"]))
        label = (
            f'<span class="label">{html.escape(str(element["name"]))} '
            f'{parse_int(element["width"])}x{parse_int(element["height"])} '
            f'@{parse_int(element["x"])},{parse_int(element["y"])}</span>'
        )
        item_html.append(
            f'<div class="element {html.escape(str(element["kind"]))}" style="{style}" {data_attrs}>{body}{label}</div>'
        )
    return f"""
      <section class="panel">
        <h2>{html.escape(title)}</h2>
        <div class="scrollbox" style="height:{scroll_height}px">
          {''.join(item_html)}
        </div>
      </section>
    """


def write_html(out_dir: Path, current: dict[str, object], reference: dict[str, object], image_dir: Path) -> Path:
    asset_dir = out_dir / "assets"
    asset_dir.mkdir(parents=True, exist_ok=True)
    for element in [*current["elements"], *reference["elements"]]:
        if element.get("kind") != "image" or element.get("missing"):
            continue
        source = image_dir / f"{element['name']}.png"
        target = asset_dir / source.name
        if source.exists():
            shutil.copy2(source, target)

    html_path = out_dir / "gacha-select-layout.html"
    html_text = f"""<!doctype html>
<meta charset="utf-8">
<title>KSSMA gacha select layout check</title>
<style>
  body {{ margin: 0; background: #171b20; color: #e9eef5; font: 14px/1.4 Arial, sans-serif; }}
  header {{ padding: 12px 18px; background: #222a32; position: sticky; top: 0; z-index: 3; }}
  main {{ display: flex; gap: 18px; padding: 18px; align-items: flex-start; }}
  .panel {{ width: 820px; }}
  h2 {{ font-size: 16px; margin: 0 0 8px; }}
  .scrollbox {{ position: relative; width: 784px; overflow: hidden; background: #26313b; border: 2px solid #6db6d9; }}
  .scrollbox::before {{ content: ""; position: absolute; inset: 0; background: linear-gradient(#ffffff10 1px, transparent 1px), linear-gradient(90deg, #ffffff10 1px, transparent 1px); background-size: 40px 40px; pointer-events: none; }}
  .element {{ position: absolute; box-sizing: border-box; outline: 2px solid #39d353; background: #00000022; }}
  .element.image {{ outline-color: #f85149; }}
  .element.text {{ outline-color: #d29922; color: white; text-shadow: 1px 1px 2px black; padding: 2px 4px; }}
  .element img {{ display: block; width: 100%; height: 100%; object-fit: fill; }}
  .label {{ position: absolute; left: 0; top: 0; transform: translateY(-100%); background: #000c; color: #fff; padding: 1px 4px; font-size: 11px; white-space: nowrap; }}
  pre {{ margin: 0 18px 18px; padding: 12px; background: #0d1117; color: #c9d1d9; white-space: pre-wrap; }}
</style>
<header>
  <strong>KSSMA gacha select layout check</strong>
  <span>red=image, yellow=text, green=other</span>
</header>
<main>
  {render_panel("current server/data/game/gacha.json", int(current["scrollHeight"]), current["elements"])}
  {render_panel("bundled local_gachaselect.xml reference", int(reference["scrollHeight"]), reference["elements"])}
</main>
<pre id="report"></pre>
<script>
function rectOf(el) {{
  const rect = el.getBoundingClientRect();
  return {{
    name: el.dataset.name,
    kind: el.dataset.kind,
    left: rect.left,
    top: rect.top,
    right: rect.right,
    bottom: rect.bottom,
    width: rect.width,
    height: rect.height
  }};
}}
function overlap(a, b) {{
  const width = Math.min(a.right, b.right) - Math.max(a.left, b.left);
  const height = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
  if (width <= 0 || height <= 0) return null;
  return {{ a: a.name, b: b.name, width, height, area: width * height }};
}}
window.collectLayoutReport = function collectLayoutReport() {{
  const panels = Array.from(document.querySelectorAll(".panel")).map(panel => {{
    const title = panel.querySelector("h2").textContent;
    const images = Array.from(panel.querySelectorAll(".element.image")).map(rectOf);
    const overlaps = [];
    for (let i = 0; i < images.length; i++) {{
      for (let j = i + 1; j < images.length; j++) {{
        const hit = overlap(images[i], images[j]);
        if (hit) overlaps.push(hit);
      }}
    }}
    return {{ title, images, overlaps }};
  }});
  const report = {{ panels }};
  document.getElementById("report").textContent = JSON.stringify(report, null, 2);
  return report;
}};
window.addEventListener("load", () => window.collectLayoutReport());
</script>
"""
    html_path.write_text(html_text, encoding="utf-8")
    return html_path


def write_editor_html(
    out_dir: Path,
    *,
    scroll_height: int,
    frame_width: int,
    display_scale: float,
    slots: list[dict[str, object]],
    current_placements: list[dict[str, object]],
    reference_placements: list[dict[str, object]],
    candidates: list[dict[str, object]],
    image_dir: Path,
) -> Path:
    asset_dir = out_dir / "assets"
    asset_dir.mkdir(parents=True, exist_ok=True)
    for candidate in candidates:
        source = image_dir / f"{candidate['name']}.png"
        target = asset_dir / source.name
        if source.exists():
            shutil.copy2(source, target)

    data = {
        "scrollHeight": scroll_height,
        "displayScale": display_scale,
        "slots": slots,
        "currentPlacements": current_placements,
        "candidates": candidates,
    }
    data_json = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    editor_path = out_dir / "gacha-select-layout-editor.html"
    editor_text = r"""<!doctype html>
<html lang="zh-CN">
<meta charset="utf-8">
<title>KSSMA gacha select manual layout editor</title>
<style>
  :root { color-scheme: dark; --stage-w: __FRAME_WIDTH__px; }
  * { box-sizing: border-box; }
  body { margin: 0; background: #12161c; color: #e8edf3; font: 14px/1.45 Arial, "Microsoft YaHei", sans-serif; }
  header { padding: 12px 16px; background: #1e2731; border-bottom: 1px solid #344150; position: sticky; top: 0; z-index: 10; }
  header strong { display: block; font-size: 16px; margin-bottom: 4px; }
  header span { color: #b7c0ca; }
  main { display: grid; grid-template-columns: __LEFT_WIDTH__px minmax(360px, 1fr); min-height: calc(100vh - 66px); }
  #left { padding: 14px; border-right: 1px solid #344150; overflow: auto; }
  #right { padding: 14px; overflow: auto; max-height: calc(100vh - 66px); }
  .toolbar { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-bottom: 10px; }
  button, select, input { background: #263241; color: #e8edf3; border: 1px solid #536273; border-radius: 4px; padding: 6px 8px; }
  button:hover { background: #334255; }
  button.primary { border-color: #58a6ff; }
  button.danger { border-color: #f85149; }
  .status { margin: 8px 0 10px; padding: 8px; background: #0d1117; border: 1px solid #30363d; white-space: pre-wrap; min-height: 38px; }
  #stageWrap { width: __STAGE_WRAP_WIDTH__px; overflow: auto; padding: 12px; background: #0b0f14; border: 1px solid #344150; }
  #stage {
    position: relative;
    width: var(--stage-w);
    min-height: 630px;
    background: #202b35;
    overflow: hidden;
    border: 2px solid #6db6d9;
    background-image:
      linear-gradient(#ffffff16 1px, transparent 1px),
      linear-gradient(90deg, #ffffff16 1px, transparent 1px),
      linear-gradient(#ffffff08 1px, transparent 1px),
      linear-gradient(90deg, #ffffff08 1px, transparent 1px);
    background-size: 40px 40px, 40px 40px, 8px 8px, 8px 8px;
  }
  .slot { position: absolute; left: 0; border: 1px dashed #58a6ff; background: #58a6ff10; cursor: pointer; }
  .slot.active { background: #58a6ff24; outline: 2px solid #58a6ff; }
  .slot-label { position: sticky; left: 0; display: inline-block; background: #08111dcc; color: #d2e9ff; padding: 2px 6px; font-size: 12px; }
  .placement { position: absolute; outline: 2px solid #f85149; cursor: pointer; user-select: none; background: #0004; }
  .placement.selected { outline: 3px solid #39d353; z-index: 5; }
  .placement.text { outline-color: #d29922; color: #fff; padding: 3px 5px; text-shadow: 1px 1px 2px #000; overflow: hidden; }
  .placement img { display: block; width: 100%; height: 100%; object-fit: fill; pointer-events: none; }
  .placement-label { position: absolute; left: 0; top: 0; transform: translateY(-100%); background: #000d; color: #fff; padding: 1px 4px; font-size: 11px; white-space: nowrap; }
  #candidates { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 10px; }
  .candidate { border: 1px solid #3d4b5c; border-radius: 6px; background: #1a212b; padding: 8px; cursor: pointer; }
  .candidate:hover { border-color: #58a6ff; }
  .candidate img { width: 100%; height: 94px; object-fit: contain; background: #090c10; border: 1px solid #303a46; }
  .candidate-name { margin-top: 6px; font-size: 12px; word-break: break-all; }
  .candidate-meta { color: #aeb8c4; font-size: 12px; }
  .tag { display: inline-block; margin-top: 4px; margin-right: 4px; padding: 1px 4px; background: #3a2530; color: #ffb4c0; border: 1px solid #6b3341; border-radius: 3px; font-size: 11px; }
  textarea { width: 100%; min-height: 170px; margin-top: 10px; background: #0d1117; color: #c9d1d9; border: 1px solid #30363d; padding: 8px; font: 12px/1.4 Consolas, monospace; }
  .hint { color: #b7c0ca; margin: 0 0 10px; }
</style>
<body>
<header>
  <strong>扭蛋页面手排工具</strong>
  <span>1. 选左边固定 XML 槽位；2. 点右边候选图替换；3. 导出 JSON 发回来。坐标按 XML，图片按客户端显示比例缩放预览。</span>
</header>
<main>
  <section id="left">
    <div class="toolbar">
      <label>当前槽位 <select id="slotSelect"></select></label>
      <button id="resetCurrent">恢复当前配置</button>
      <button id="validate" class="primary">检查重叠</button>
      <button id="export" class="primary">导出 JSON</button>
      <button id="import">导入 JSON</button>
    </div>
    <div id="status" class="status"></div>
    <div id="stageWrap"><div id="stage"></div></div>
    <textarea id="exportText" spellcheck="false" placeholder="点击“导出 JSON”后，把这里的内容发回来。也可以把上次导出的 JSON 粘贴到这里，再点“导入 JSON”。"></textarea>
  </section>
  <section id="right">
    <p class="hint">候选图来自 <code>work/gacha-image-preview/decoded</code>。标着 rejected/generated 的图只作为对照。缩略尺寸显示为客户端逻辑尺寸。</p>
    <input id="filter" placeholder="筛选文件名，例如 free / cp / banner" style="width:100%; margin-bottom:10px;">
    <div id="candidates"></div>
  </section>
</main>
<script id="initial-data" type="application/json">__DATA__</script>
<script>
const initialData = JSON.parse(document.getElementById("initial-data").textContent);
let state = {
  scrollHeight: initialData.scrollHeight,
  displayScale: initialData.displayScale,
  slots: initialData.slots,
  placements: clone(initialData.currentPlacements),
  candidates: initialData.candidates
};
let activeSlot = state.slots[0]?.id || "";
let selectedId = state.placements.find(p => p.kind === "image")?.id || "";

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}
function byId(id) {
  return state.placements.find(p => p.id === id);
}
function candidateByName(name) {
  return state.candidates.find(c => c.name === name);
}
function slotById(id) {
  return state.slots.find(s => s.id === id);
}
function setStatus(text) {
  document.getElementById("status").textContent = text;
}
function setActiveSlot(id) {
  activeSlot = id;
  const select = document.getElementById("slotSelect");
  select.value = id;
  renderSlots();
  updateStatus();
}
function selectPlacement(id) {
  selectedId = id;
  const p = byId(id);
  if (p?.slot) activeSlot = p.slot;
  document.getElementById("slotSelect").value = activeSlot;
  renderPlacements();
  renderSlots();
  updateStatus();
}
function updateStatus(extra = "") {
  const selected = byId(selectedId);
  const slot = slotById(activeSlot);
  const lines = [
    `槽位: ${slot ? `${slot.label} (${slot.id}) XML x=${slot.contentX}, y=${slot.y}, frame=${slot.width}x${slot.height}` : activeSlot}`,
    selected ? `选中: ${selected.kind === "image" ? selected.name : "text"} @ ${selected.x},${selected.y}, display ${selected.width}x${selected.height}` : "选中: 无",
    `提示: 这里只能换图，不能移动坐标。导出使用 XML x/y；预览缩放比例 ${state.displayScale.toFixed(3)}。`
  ];
  if (extra) lines.unshift(extra);
  setStatus(lines.join("\n"));
}
function renderSlotSelect() {
  const select = document.getElementById("slotSelect");
  select.innerHTML = "";
  for (const slot of state.slots) {
    const option = document.createElement("option");
    option.value = slot.id;
    option.textContent = `${slot.label} (${slot.id})`;
    select.appendChild(option);
  }
  select.value = activeSlot;
}
function renderSlots() {
  const stage = document.getElementById("stage");
  stage.querySelectorAll(".slot").forEach(el => el.remove());
  for (const slot of state.slots) {
    const el = document.createElement("div");
    el.className = `slot ${slot.id === activeSlot ? "active" : ""}`;
    el.dataset.slotId = slot.id;
    el.style.left = `${slot.x}px`;
    el.style.top = `${slot.y}px`;
    el.style.width = `${slot.width}px`;
    el.style.height = `${slot.height}px`;
    el.innerHTML = `<span class="slot-label">${slot.label} / XML ${slot.sourceImage} / ${slot.height}px</span>`;
    stage.prepend(el);
  }
}
function renderPlacements() {
  const stage = document.getElementById("stage");
  stage.querySelectorAll(".placement").forEach(el => el.remove());
  for (const p of state.placements) {
    const el = document.createElement("div");
    el.className = `placement ${p.kind || "image"} ${p.id === selectedId ? "selected" : ""}`;
    el.dataset.id = p.id;
    el.style.left = `${p.x}px`;
    el.style.top = `${p.y}px`;
    el.style.width = `${p.width}px`;
    el.style.height = `${p.height}px`;
    const natural = p.kind === "image" && p.naturalWidth ? ` natural ${p.naturalWidth}x${p.naturalHeight}` : "";
    const label = `<span class="placement-label">${p.kind === "image" ? p.name : "text"} display ${p.width}x${p.height}${natural} @${p.x},${p.y}</span>`;
    if (p.kind === "image") {
      el.innerHTML = `<img src="${p.src}" alt="${p.name}">${label}`;
    } else {
      el.textContent = p.text || p.name || "";
      el.insertAdjacentHTML("beforeend", label);
    }
    stage.appendChild(el);
  }
}
function renderCandidates() {
  const filter = document.getElementById("filter").value.trim().toLowerCase();
  const root = document.getElementById("candidates");
  root.innerHTML = "";
  for (const candidate of state.candidates) {
    if (filter && !candidate.name.toLowerCase().includes(filter)) continue;
    const el = document.createElement("div");
    el.className = "candidate";
    el.dataset.name = candidate.name;
    const tags = (candidate.notes || []).map(note => `<span class="tag">${note}</span>`).join("");
    el.innerHTML = `
      <img src="${candidate.src}" alt="${candidate.name}">
      <div class="candidate-name">${candidate.name}</div>
      <div class="candidate-meta">display ${candidate.width}x${candidate.height} / png ${candidate.naturalWidth}x${candidate.naturalHeight}</div>
      ${tags}
    `;
    root.appendChild(el);
  }
}
function firstImageInActiveSlot() {
  return state.placements.find(p => p.kind === "image" && p.slot === activeSlot);
}
function createImagePlacement(candidate) {
  const slot = slotById(activeSlot) || state.slots[0] || { x: 0, y: 0 };
  const id = `manual-${Date.now()}`;
  const placement = {
    id,
    slot: activeSlot,
    order: state.placements.length,
    kind: "image",
    name: candidate.name,
    src: candidate.src,
    x: slot.contentX ?? slot.x,
    y: slot.y,
    width: candidate.width,
    height: candidate.height,
    naturalWidth: candidate.naturalWidth,
    naturalHeight: candidate.naturalHeight,
    naturalWidth: candidate.naturalWidth,
    naturalHeight: candidate.naturalHeight,
    actionId: activeSlot === "paid_mc" || activeSlot === "ticket" ? 2 : 1,
    se: "se_def_cancel_04_01",
    behavior: activeSlot === "paid_mc" ? "2,0,0,0" : activeSlot === "ticket" ? "0,0,0,0" : "1,1,1,0"
  };
  state.placements.push(placement);
  return placement;
}
function applyCandidate(candidateName) {
  const candidate = candidateByName(candidateName);
  if (!candidate) return;
  let target = byId(selectedId);
  if (!target || target.kind !== "image") target = firstImageInActiveSlot();
  if (!target) target = createImagePlacement(candidate);
  target.kind = "image";
  target.slot = activeSlot;
  target.name = candidate.name;
  target.src = candidate.src;
  target.width = candidate.width;
  target.height = candidate.height;
  target.naturalWidth = candidate.naturalWidth;
  target.naturalHeight = candidate.naturalHeight;
  const slot = slotById(activeSlot);
  if (slot) {
    target.x = slot.contentX ?? slot.x;
    target.y = slot.y;
  }
  selectedId = target.id;
  renderPlacements();
  updateStatus(`已把 ${candidate.name} 放到 ${SLOT_LABEL(activeSlot)}。`);
}
function SLOT_LABEL(id) {
  return slotById(id)?.label || id;
}
function rect(p) {
  return { left: p.x, top: p.y, right: p.x + p.width, bottom: p.y + p.height };
}
function overlap(a, b) {
  const ra = rect(a), rb = rect(b);
  const width = Math.min(ra.right, rb.right) - Math.max(ra.left, rb.left);
  const height = Math.min(ra.bottom, rb.bottom) - Math.max(ra.top, rb.top);
  if (width <= 0 || height <= 0) return null;
  return { a: a.name, b: b.name, width, height, area: width * height };
}
function validateLayout() {
  const images = state.placements.filter(p => p.kind === "image");
  const overlaps = [];
  for (let i = 0; i < images.length; i++) {
    for (let j = i + 1; j < images.length; j++) {
      const hit = overlap(images[i], images[j]);
      if (hit) overlaps.push(hit);
    }
  }
  const overflow = images.filter(p => p.y + p.height > state.scrollHeight).map(p => `${p.name} bottom=${p.y + p.height}`);
  const lines = [];
  lines.push(overlaps.length ? `图片重叠: ${JSON.stringify(overlaps)}` : "图片重叠: 无");
  lines.push(overflow.length ? `超出 scrollHeight=${state.scrollHeight}: ${overflow.join("; ")}` : "超出: 无");
  updateStatus(lines.join("\n"));
}
function contentFromPlacement(p) {
  if (p.kind === "text") {
    return {
      actionId: p.actionId || 0,
      x: p.x,
      y: p.y,
      textMessages: p.textMessages && p.textMessages.length ? p.textMessages : [{ text: p.text || p.name || "", color: "0xFFFFFF", size: 18 }]
    };
  }
  const slot = slotById(p.slot);
  const x = slot ? (slot.contentX ?? slot.x) : p.x;
  const y = slot ? slot.y : p.y;
  const content = {
    actionId: p.actionId || 0,
    imagefile: p.name,
    x,
    y
  };
  if (p.se) content.se = p.se;
  if (p.message) content.message = p.message;
  if (p.behavior) content.behavior = p.behavior;
  return content;
}
function exportLayout() {
  const placements = state.placements.map(p => ({ ...p }));
  const contents = placements
    .slice()
    .sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
    .map(contentFromPlacement);
  const output = {
    note: "paste this back to Codex; server/data/game/gacha.json should only use page.contents, not this note",
    scrollHeight: state.scrollHeight,
    placements,
    page: { scrollHeight: state.scrollHeight, contents }
  };
  document.getElementById("exportText").value = JSON.stringify(output, null, 2);
  validateLayout();
}
function normalizeImportedPlacement(p, index) {
  const candidate = p.kind === "image" ? candidateByName(p.name || p.imagefile) : null;
  const kind = p.kind || (p.imagefile ? "image" : "text");
  const slot = kind === "image" && p.slot ? slotById(p.slot) : null;
  return {
    ...p,
    id: p.id || `import-${index}`,
    kind,
    name: p.name || p.imagefile || p.text || "text",
    src: p.src || (candidate ? candidate.src : `assets/${p.imagefile || p.name}.png`),
    width: Number(p.width || candidate?.width || 160),
    height: Number(p.height || candidate?.height || 30),
    naturalWidth: Number(p.naturalWidth || candidate?.naturalWidth || p.width || 160),
    naturalHeight: Number(p.naturalHeight || candidate?.naturalHeight || p.height || 30),
    x: Number(slot ? (slot.contentX ?? slot.x) : p.x || 0),
    y: Number(slot ? slot.y : p.y || 0),
    order: Number(p.order ?? index),
    slot: p.slot || activeSlot
  };
}
function importLayout() {
  const text = document.getElementById("exportText").value;
  if (!text.trim()) return;
  const parsed = JSON.parse(text);
  if (Array.isArray(parsed.placements)) {
    state.placements = parsed.placements.map(normalizeImportedPlacement);
  } else if (parsed.page && Array.isArray(parsed.page.contents)) {
    state.placements = parsed.page.contents.map((content, index) => {
      const imageName = content.imagefile;
      const candidate = imageName ? candidateByName(imageName) : null;
      return normalizeImportedPlacement({
        id: `import-content-${index}`,
        kind: imageName ? "image" : "text",
        name: imageName || "text",
        src: imageName ? `assets/${imageName}.png` : "",
        width: candidate?.width || 160,
        height: candidate?.height || 30,
        x: content.x,
        y: content.y,
        actionId: content.actionId,
        se: content.se,
        message: content.message,
        behavior: content.behavior,
        textMessages: content.textMessages || [],
        text: (content.textMessages || []).map(m => m.text || "").join("")
      }, index);
    });
  } else {
    throw new Error("JSON must contain placements or page.contents");
  }
  selectedId = state.placements.find(p => p.kind === "image")?.id || "";
  renderPlacements();
  updateStatus("已导入。");
}
function resetTo(placements) {
  state.placements = clone(placements);
  selectedId = state.placements.find(p => p.kind === "image")?.id || "";
  renderPlacements();
  updateStatus("已重置。");
}

document.getElementById("stage").style.height = `${state.scrollHeight}px`;
renderSlotSelect();
renderSlots();
renderPlacements();
renderCandidates();
updateStatus();

document.getElementById("slotSelect").addEventListener("change", event => setActiveSlot(event.target.value));
document.getElementById("filter").addEventListener("input", renderCandidates);
document.getElementById("resetCurrent").addEventListener("click", () => resetTo(initialData.currentPlacements));
document.getElementById("validate").addEventListener("click", validateLayout);
document.getElementById("export").addEventListener("click", exportLayout);
document.getElementById("import").addEventListener("click", () => {
  try { importLayout(); } catch (error) { updateStatus(`导入失败: ${error.message}`); }
});
document.getElementById("right").addEventListener("click", event => {
  const card = event.target.closest(".candidate");
  if (!card) return;
  applyCandidate(card.dataset.name);
});
document.getElementById("stage").addEventListener("pointerdown", event => {
  const placementEl = event.target.closest(".placement");
  if (placementEl) {
    const p = byId(placementEl.dataset.id);
    if (!p) return;
    selectPlacement(p.id);
    event.preventDefault();
    return;
  }
  const slotEl = event.target.closest(".slot");
  if (slotEl) setActiveSlot(slotEl.dataset.slotId);
});
</script>
</body>
</html>
"""
    editor_text = (
        editor_text.replace("__DATA__", data_json)
        .replace("__FRAME_WIDTH__", str(frame_width))
        .replace("__LEFT_WIDTH__", str(frame_width + 120))
        .replace("__STAGE_WRAP_WIDTH__", str(frame_width + 28))
    )
    editor_path.write_text(editor_text, encoding="utf-8")
    return editor_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--xml", type=Path, default=DEFAULT_XML)
    parser.add_argument("--layout", type=Path, default=DEFAULT_LAYOUT)
    parser.add_argument("--image-dir", type=Path, default=DEFAULT_IMAGE_DIR)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--editor", action="store_true")
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    current_scroll, current_contents = read_json_contents(args.json, "main")
    reference_scroll, reference_contents = read_xml_contents(args.xml)
    frame_width = read_layout_frame_width(args.layout)
    display_scale = infer_display_scale(reference_contents + current_contents, args.image_dir, frame_width)
    current_elements = build_elements(current_contents, args.image_dir, "current", display_scale)
    reference_elements = build_elements(reference_contents, args.image_dir, "reference", display_scale)
    current = {
        "scrollHeight": current_scroll,
        "elements": current_elements,
        "issues": collect_static_issues(current_elements, current_scroll),
    }
    reference = {
        "scrollHeight": reference_scroll,
        "elements": reference_elements,
        "issues": collect_static_issues(reference_elements, reference_scroll),
    }
    report = {
        "inputs": {
            "json": str(args.json.relative_to(ROOT)),
            "xml": str(args.xml.relative_to(ROOT)),
            "layout": str(args.layout.relative_to(ROOT)),
            "imageDir": str(args.image_dir.relative_to(ROOT)),
            "frameWidth": frame_width,
            "displayScale": display_scale,
        },
        "current": current,
        "reference": reference,
    }
    report_path = args.out_dir / "gacha-select-layout-report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    html_path = write_html(args.out_dir, current, reference, args.image_dir)
    print(f"html={html_path.relative_to(ROOT).as_posix()}")
    print(f"report={report_path.relative_to(ROOT).as_posix()}")
    if args.editor:
        candidates = read_image_candidates(args.image_dir, display_scale)
        slots = read_xml_slots(reference_contents, reference_scroll, args.image_dir, frame_width)
        current_placements = build_locked_editor_placements(
            current_contents, reference_contents, args.image_dir, "current", display_scale
        )
        reference_placements = build_editor_placements(reference_contents, args.image_dir, "xml", display_scale)
        editor_path = write_editor_html(
            args.out_dir,
            scroll_height=max(current_scroll, reference_scroll),
            frame_width=frame_width,
            display_scale=display_scale,
            slots=slots,
            current_placements=current_placements,
            reference_placements=reference_placements,
            candidates=candidates,
            image_dir=args.image_dir,
        )
        print(f"editor={editor_path.relative_to(ROOT).as_posix()}")
    print(f"current_overlaps={len(current['issues']['overlaps'])}")
    if args.check:
        failures = []
        if current["issues"]["missing"]:
            failures.append(f"missing={current['issues']['missing']}")
        if current["issues"]["overflow"]:
            failures.append(f"overflow={current['issues']['overflow']}")
        if current["issues"]["overlaps"]:
            failures.append(f"overlaps={current['issues']['overlaps']}")
        if failures:
            raise SystemExit("; ".join(failures))


if __name__ == "__main__":
    main()
