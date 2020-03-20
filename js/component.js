const getComponentsEnv = (componentsRoot, getMemory, customEventCallback) => {
  const TAG_DIV = 1;
  const TAG_P = 2;
  const TAG_BUTTON = 3;

  const CLASS_HORIZONTAL = 1;
  const CLASS_VERTICAL = 2;
  const CLASS_FLEX = 3;
  const CLASS_GRID = 4;
  const CLASSES = {
    1: "horizontal",
    2: "vertical",
    3: "flex",
    4: "grid"
  };

  let elements = [];
  let unused_ids = [];
  let clickEvents = {};
  let hoverEvents = {};

  const encodeArea = areaInt => {
    const CIPHER = {
      "0": "a",
      "1": "b",
      "2": "c",
      "3": "d",
      "4": "e",
      "5": "f",
      "6": "g",
      "7": "h",
      "8": "i",
      "9": "j"
    };
    let str = "";
    let rawStr = areaInt.toString();
    for (let c of rawStr) {
      str += CIPHER[c];
    }
    return str;
  };

  return {
    element_render_begin: () => {
      // Clear all elements from root component
      while (componentsRoot.firstChild) {
        componentsRoot.removeChild(componentsRoot.firstChild);
      }
      // Create an id for the zig code to reference
      const id = elements.length;
      elements.push(componentsRoot);
      return id;
    },
    element_render_end: () => (elements = []),

    element_create: tag => {
      let elementStr = "";
      switch (tag) {
        case TAG_DIV:
          elementStr = "div";
          break;
        case TAG_P:
          elementStr = "p";
          break;
        case TAG_BUTTON:
          elementStr = "button";
          break;
        default:
          console.log("Unknown tag number, rendering component as a div");
          elementStr = "div";
          break;
      }
      const element = document.createElement(elementStr);
      element.classList.add("component");
      const id = unused_ids.length > 0 ? unused_ids.pop() : elements.length;
      elements[id] = element;
      return id;
    },

    element_remove: elemId => {
      if (elemId < elements.length && !unused_ids.includes(elemId)) {
        elements[elemId].remove();
        elements[elemId] = null;
        unused_ids.push(elemId);
      }
    },

    element_setTextS: (elemId, textPtr, textLen) => {
      const element = elements[elemId];
      const bytes = new Uint8Array(getMemory().buffer, textPtr, textLen);
      let s = "";
      for (const b of bytes) {
        s += String.fromCharCode(b);
      }
      element.textContent = s;
    },

    element_setClickEvent: (elemId, clickEvent) => {
      clickEvents[elemId] = () => customEventCallback(clickEvent);
      elements[elemId].addEventListener("click", clickEvents[elemId]);
    },

    element_removeClickEvent: (elemId, clickEvent) => {
      elements[elemId].removeEventListener("click", clickEvents[elemId]);
    },

    element_setHoverEvent: (elemId, hoverEvent) => {
      hoverEvents[elemId] = () => customEventCallback(hoverEvent);
      elements[elemId].addEventListener("mouseover", hoverEvents[elemId]);
    },

    element_removeHoverEvent: (elemId, clickEvent) => {
      elements[elemId].removeEventListener("click", hoverEvents[elemId]);
    },

    element_addClass: (elemId, classNumber) => {
      let classStr = CLASSES[classNumber];
      if (classStr === undefined) {
        console.log("Unknown class number", classNumber);
        return;
      }
      elements[elemId].classList.add(classStr);
    },

    element_setGridArea: (elemId, grid_area) => {
      elements[elemId].style.gridArea = encodeArea(grid_area);
    },

    element_setGridTemplateAreasS: (elemId, templatePtr, width, height) => {
      let templateStr = "";
      const areaInts = new Uint32Array(
        getMemory().buffer,
        templatePtr,
        width * height
      );
      for (let j = 0; j < height; j += 1) {
        templateStr += '"';
        for (let i = 0; i < width; i += 1) {
          templateStr += encodeArea(areaInts[j * width + i]);
          templateStr += " ";
        }
        templateStr += '"';
      }
      elements[elemId].style.gridTemplateAreas = templateStr;
    },

    element_setGridTemplateRowsS: (elemId, colsPtr, colsLen) => {
      const numbers = new Uint32Array(getMemory().buffer, colsPtr, colsLen);
      let s = "";
      for (const num of numbers) {
        s += num;
        s += "fr ";
      }
      elements[elemId].style.gridTemplateRows = s;
    },

    element_setGridTemplateColumnsS: (elemId, colsPtr, colsLen) => {
      const numbers = new Uint32Array(getMemory().buffer, colsPtr, colsLen);
      let s = "";
      for (const num of numbers) {
        s += num;
        s += "fr ";
      }
      elements[elemId].style.gridTemplateColumns = s;
    },

    element_appendChild: (parentElemId, childElemId) => {
      const parentElem = elements[parentElemId];
      const childElem = elements[childElemId];
      parentElem.appendChild(childElem);
    }
  };
};

export default getComponentsEnv;
