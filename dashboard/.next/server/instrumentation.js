"use strict";
/*
 * ATTENTION: An "eval-source-map" devtool has been used.
 * This devtool is neither made for production nor for readable output files.
 * It uses "eval()" calls to create a separate source file with attached SourceMaps in the browser devtools.
 * If you are trying to read the output file, select a different devtool (https://webpack.js.org/configuration/devtool/)
 * or disable the default devtool with "devtool: false".
 * If you are looking for production-ready output files, see mode: "production" (https://webpack.js.org/configuration/mode/).
 */
(() => {
var exports = {};
exports.id = "instrumentation";
exports.ids = ["instrumentation"];
exports.modules = {

/***/ "(instrument)/./instrumentation.ts":
/*!****************************!*\
  !*** ./instrumentation.ts ***!
  \****************************/
/***/ ((__unused_webpack_module, __webpack_exports__, __webpack_require__) => {

eval("__webpack_require__.r(__webpack_exports__);\n/* harmony export */ __webpack_require__.d(__webpack_exports__, {\n/* harmony export */   register: () => (/* binding */ register)\n/* harmony export */ });\nasync function register() {\n    // Node.js 22+ ships a partial localStorage stub without getItem/setItem.\n    // Patch it so SSR-imported client packages don't crash.\n    if (typeof global !== \"undefined\" && (typeof global.localStorage === \"undefined\" || typeof global.localStorage?.getItem !== \"function\")) {\n        const store = {};\n        global.localStorage = {\n            getItem: (k)=>store[k] ?? null,\n            setItem: (k, v)=>{\n                store[k] = v;\n            },\n            removeItem: (k)=>{\n                delete store[k];\n            },\n            clear: ()=>{\n                for(const k in store)delete store[k];\n            },\n            key: (i)=>Object.keys(store)[i] ?? null,\n            get length () {\n                return Object.keys(store).length;\n            }\n        };\n    }\n}\n//# sourceURL=[module]\n//# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiKGluc3RydW1lbnQpLy4vaW5zdHJ1bWVudGF0aW9uLnRzIiwibWFwcGluZ3MiOiI7Ozs7QUFBTyxlQUFlQTtJQUNwQix5RUFBeUU7SUFDekUsd0RBQXdEO0lBQ3hELElBQ0UsT0FBT0MsV0FBVyxlQUNqQixRQUFPLE9BQStDQyxZQUFZLEtBQUssZUFDdEUsT0FBTyxPQUErQ0EsWUFBWSxFQUFFQyxZQUFZLFVBQVMsR0FDM0Y7UUFDQSxNQUFNQyxRQUFnQyxDQUFDO1FBQ3JDSCxPQUE4Q0MsWUFBWSxHQUFHO1lBQzdEQyxTQUFTLENBQUNFLElBQWNELEtBQUssQ0FBQ0MsRUFBRSxJQUFJO1lBQ3BDQyxTQUFTLENBQUNELEdBQVdFO2dCQUFnQkgsS0FBSyxDQUFDQyxFQUFFLEdBQUdFO1lBQUU7WUFDbERDLFlBQVksQ0FBQ0g7Z0JBQWdCLE9BQU9ELEtBQUssQ0FBQ0MsRUFBRTtZQUFDO1lBQzdDSSxPQUFPO2dCQUFRLElBQUssTUFBTUosS0FBS0QsTUFBTyxPQUFPQSxLQUFLLENBQUNDLEVBQUU7WUFBQztZQUN0REssS0FBSyxDQUFDQyxJQUFjQyxPQUFPQyxJQUFJLENBQUNULE1BQU0sQ0FBQ08sRUFBRSxJQUFJO1lBQzdDLElBQUlHLFVBQVM7Z0JBQUUsT0FBT0YsT0FBT0MsSUFBSSxDQUFDVCxPQUFPVSxNQUFNO1lBQUM7UUFDbEQ7SUFDRjtBQUNGIiwic291cmNlcyI6WyIvVXNlcnMvdGhlb2RhZ3VpZXIvRGV2ZWxvcGVyL3BlcnNvbmFsL2ZvdW5kcnkvZGFzaGJvYXJkL2luc3RydW1lbnRhdGlvbi50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJleHBvcnQgYXN5bmMgZnVuY3Rpb24gcmVnaXN0ZXIoKSB7XG4gIC8vIE5vZGUuanMgMjIrIHNoaXBzIGEgcGFydGlhbCBsb2NhbFN0b3JhZ2Ugc3R1YiB3aXRob3V0IGdldEl0ZW0vc2V0SXRlbS5cbiAgLy8gUGF0Y2ggaXQgc28gU1NSLWltcG9ydGVkIGNsaWVudCBwYWNrYWdlcyBkb24ndCBjcmFzaC5cbiAgaWYgKFxuICAgIHR5cGVvZiBnbG9iYWwgIT09IFwidW5kZWZpbmVkXCIgJiZcbiAgICAodHlwZW9mIChnbG9iYWwgYXMgdW5rbm93biBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPikubG9jYWxTdG9yYWdlID09PSBcInVuZGVmaW5lZFwiIHx8XG4gICAgICB0eXBlb2YgKGdsb2JhbCBhcyB1bmtub3duIGFzIFJlY29yZDxzdHJpbmcsIFN0b3JhZ2U+KS5sb2NhbFN0b3JhZ2U/LmdldEl0ZW0gIT09IFwiZnVuY3Rpb25cIilcbiAgKSB7XG4gICAgY29uc3Qgc3RvcmU6IFJlY29yZDxzdHJpbmcsIHN0cmluZz4gPSB7fVxuICAgIDsoZ2xvYmFsIGFzIHVua25vd24gYXMgUmVjb3JkPHN0cmluZywgU3RvcmFnZT4pLmxvY2FsU3RvcmFnZSA9IHtcbiAgICAgIGdldEl0ZW06IChrOiBzdHJpbmcpID0+IHN0b3JlW2tdID8/IG51bGwsXG4gICAgICBzZXRJdGVtOiAoazogc3RyaW5nLCB2OiBzdHJpbmcpID0+IHsgc3RvcmVba10gPSB2IH0sXG4gICAgICByZW1vdmVJdGVtOiAoazogc3RyaW5nKSA9PiB7IGRlbGV0ZSBzdG9yZVtrXSB9LFxuICAgICAgY2xlYXI6ICgpID0+IHsgZm9yIChjb25zdCBrIGluIHN0b3JlKSBkZWxldGUgc3RvcmVba10gfSxcbiAgICAgIGtleTogKGk6IG51bWJlcikgPT4gT2JqZWN0LmtleXMoc3RvcmUpW2ldID8/IG51bGwsXG4gICAgICBnZXQgbGVuZ3RoKCkgeyByZXR1cm4gT2JqZWN0LmtleXMoc3RvcmUpLmxlbmd0aCB9LFxuICAgIH1cbiAgfVxufVxuIl0sIm5hbWVzIjpbInJlZ2lzdGVyIiwiZ2xvYmFsIiwibG9jYWxTdG9yYWdlIiwiZ2V0SXRlbSIsInN0b3JlIiwiayIsInNldEl0ZW0iLCJ2IiwicmVtb3ZlSXRlbSIsImNsZWFyIiwia2V5IiwiaSIsIk9iamVjdCIsImtleXMiLCJsZW5ndGgiXSwiaWdub3JlTGlzdCI6W10sInNvdXJjZVJvb3QiOiIifQ==\n//# sourceURL=webpack-internal:///(instrument)/./instrumentation.ts\n");

/***/ })

};
;

// load runtime
var __webpack_require__ = require("./webpack-runtime.js");
__webpack_require__.C(exports);
var __webpack_exec__ = (moduleId) => (__webpack_require__(__webpack_require__.s = moduleId))
var __webpack_exports__ = (__webpack_exec__("(instrument)/./instrumentation.ts"));
module.exports = __webpack_exports__;

})();