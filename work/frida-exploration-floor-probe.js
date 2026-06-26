// Diagnostic-only Frida probe for the ARM19 exploration floor transition.
// It does not patch code; it only logs native calls and model/list counts.
(function () {
  const lib = "librooneyj.so";
  const mod = Process.findModuleByName(lib);
  const base = mod && mod.base;
  if (base === null) {
    console.log("[kssma-probe] " + lib + " not loaded");
    return;
  }

  function taddr(offset) {
    return base.add(offset + 1); // ARM Thumb entry.
  }

  function hex(p) {
    return p ? p.toString() : "0x0";
  }

  function u32(p) {
    try {
      return Memory.readU32(p);
    } catch (_) {
      return null;
    }
  }

  function ptrAt(p) {
    try {
      return Memory.readPointer(p);
    } catch (_) {
      return ptr(0);
    }
  }

  function countVector(obj, offset, stride) {
    try {
      const begin = ptrAt(obj.add(offset));
      const end = ptrAt(obj.add(offset + 4));
      if (begin.isNull() || end.isNull()) {
        return 0;
      }
      return end.sub(begin).toInt32() / stride;
    } catch (_) {
      return null;
    }
  }

  function modelFromArea(area) {
    const holder = ptrAt(area.add(0x5c));
    if (holder.isNull()) {
      return ptr(0);
    }
    return ptrAt(holder);
  }

  function logArea(label, area) {
    const model = modelFromArea(area);
    const state = u32(area.add(0x3c));
    const f55 = u32(area.add(0x54));
    const f56 = u32(area.add(0x56));
    const floorCount = model.isNull() ? null : countVector(model, 0x58, 8);
    const sceneCount = countVector(area, 0x7c, 8);
    console.log(
      "[kssma-probe] " + label +
        " area=" + hex(area) +
        " state=" + state +
        " flag55?=" + f55 +
        " flag56?=" + f56 +
        " model=" + hex(model) +
        " model.floorInfoList.count=" + floorCount +
        " scene.floorList.count=" + sceneCount
    );
  }

  const seenPre = {};
  console.log("[kssma-probe] base=" + base);

  Interceptor.attach(taddr(0x001d7ae8), {
    onEnter(args) {
      console.log("[kssma-probe] ExplorationModel.floor this=" + hex(args[0]) + " area_id=" + args[1].toInt32());
    },
    onLeave(retval) {
      console.log("[kssma-probe] ExplorationModel.floor return=" + retval);
    },
  });

  Interceptor.attach(taddr(0x001d6d3c), {
    onEnter(args) {
      this.model = args[0];
      const reqKind = u32(this.model.add(0x2c));
      if (reqKind === 2) {
        console.log("[kssma-probe] ExplorationModel.update ENTER floor-branch model=" + hex(this.model) + " kind=" + reqKind);
      }
    },
    onLeave(retval) {
      const reqKind = u32(this.model.add(0x2c));
      const floorCount = countVector(this.model, 0x58, 8);
      if (reqKind === 0 || floorCount) {
        console.log("[kssma-probe] ExplorationModel.update LEAVE model=" + hex(this.model) + " kind=" + reqKind + " floorInfoList.count=" + floorCount);
      }
    },
  });

  Interceptor.attach(taddr(0x001d5e84), {
    onEnter(args) {
      this.model = args[0];
      console.log("[kssma-probe] ExplorationModel.initFloor ENTER model=" + hex(this.model) + " floorInfoList.count.before=" + countVector(this.model, 0x58, 8));
    },
    onLeave(retval) {
      console.log("[kssma-probe] ExplorationModel.initFloor LEAVE model=" + hex(this.model) + " areaId=" + u32(this.model.add(0xf4)) + " floorInfoList.count.after=" + countVector(this.model, 0x58, 8));
    },
  });

  Interceptor.attach(taddr(0x003419cc), {
    onEnter(args) {
      this.area = args[0];
      logArea("createFloorList ENTER", this.area);
    },
    onLeave(retval) {
      logArea("createFloorList LEAVE", this.area);
    },
  });

  Interceptor.attach(taddr(0x00341f20), {
    onEnter(args) {
      const area = args[0];
      const state = u32(area.add(0x3c));
      const key = hex(area);
      if (state === 3 || seenPre[key] !== state) {
        seenPre[key] = state;
        logArea("preUpdate ENTER", area);
      }
    },
  });
})();
