// runtime can't be in strict mode because a global variable is assign and maybe created.
/*
 * ATTENTION: An "eval-source-map" devtool has been used.
 * This devtool is neither made for production nor for readable output files.
 * It uses "eval()" calls to create a separate source file with attached SourceMaps in the browser devtools.
 * If you are trying to read the output file, select a different devtool (https://webpack.js.org/configuration/devtool/)
 * or disable the default devtool with "devtool: false".
 * If you are looking for production-ready output files, see mode: "production" (https://webpack.js.org/configuration/mode/).
 */
(self["webpackChunk_N_E"] = self["webpackChunk_N_E"] || []).push([["instrumentation"],{

/***/ "(instrument)/./instrumentation.ts":
/*!****************************!*\
  !*** ./instrumentation.ts ***!
  \****************************/
/***/ ((__unused_webpack_module, __webpack_exports__, __webpack_require__) => {

"use strict";
eval("__webpack_require__.r(__webpack_exports__);\n/* harmony export */ __webpack_require__.d(__webpack_exports__, {\n/* harmony export */   register: () => (/* binding */ register)\n/* harmony export */ });\nasync function register() {\n    // Node.js 22+ ships a partial localStorage stub without getItem/setItem.\n    // Patch it so SSR-imported client packages don't crash.\n    if (typeof __webpack_require__.g !== \"undefined\" && (typeof __webpack_require__.g.localStorage === \"undefined\" || typeof __webpack_require__.g.localStorage?.getItem !== \"function\")) {\n        const store = {};\n        __webpack_require__.g.localStorage = {\n            getItem: (k)=>store[k] ?? null,\n            setItem: (k, v)=>{\n                store[k] = v;\n            },\n            removeItem: (k)=>{\n                delete store[k];\n            },\n            clear: ()=>{\n                for(const k in store)delete store[k];\n            },\n            key: (i)=>Object.keys(store)[i] ?? null,\n            get length () {\n                return Object.keys(store).length;\n            }\n        };\n    }\n}\n//# sourceURL=[module]\n//# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiKGluc3RydW1lbnQpLy4vaW5zdHJ1bWVudGF0aW9uLnRzIiwibWFwcGluZ3MiOiI7Ozs7QUFBTyxlQUFlQTtJQUNwQix5RUFBeUU7SUFDekUsd0RBQXdEO0lBQ3hELElBQ0UsT0FBT0MscUJBQU1BLEtBQUssZUFDakIsUUFBTyxzQkFBK0NDLFlBQVksS0FBSyxlQUN0RSxPQUFPLHNCQUErQ0EsWUFBWSxFQUFFQyxZQUFZLFVBQVMsR0FDM0Y7UUFDQSxNQUFNQyxRQUFnQyxDQUFDO1FBQ3JDSCxxQkFBTUEsQ0FBd0NDLFlBQVksR0FBRztZQUM3REMsU0FBUyxDQUFDRSxJQUFjRCxLQUFLLENBQUNDLEVBQUUsSUFBSTtZQUNwQ0MsU0FBUyxDQUFDRCxHQUFXRTtnQkFBZ0JILEtBQUssQ0FBQ0MsRUFBRSxHQUFHRTtZQUFFO1lBQ2xEQyxZQUFZLENBQUNIO2dCQUFnQixPQUFPRCxLQUFLLENBQUNDLEVBQUU7WUFBQztZQUM3Q0ksT0FBTztnQkFBUSxJQUFLLE1BQU1KLEtBQUtELE1BQU8sT0FBT0EsS0FBSyxDQUFDQyxFQUFFO1lBQUM7WUFDdERLLEtBQUssQ0FBQ0MsSUFBY0MsT0FBT0MsSUFBSSxDQUFDVCxNQUFNLENBQUNPLEVBQUUsSUFBSTtZQUM3QyxJQUFJRyxVQUFTO2dCQUFFLE9BQU9GLE9BQU9DLElBQUksQ0FBQ1QsT0FBT1UsTUFBTTtZQUFDO1FBQ2xEO0lBQ0Y7QUFDRiIsInNvdXJjZXMiOlsiL1VzZXJzL3RoZW9kYWd1aWVyL0RldmVsb3Blci9wZXJzb25hbC9mb3VuZHJ5L2Rhc2hib2FyZC9pbnN0cnVtZW50YXRpb24udHMiXSwic291cmNlc0NvbnRlbnQiOlsiZXhwb3J0IGFzeW5jIGZ1bmN0aW9uIHJlZ2lzdGVyKCkge1xuICAvLyBOb2RlLmpzIDIyKyBzaGlwcyBhIHBhcnRpYWwgbG9jYWxTdG9yYWdlIHN0dWIgd2l0aG91dCBnZXRJdGVtL3NldEl0ZW0uXG4gIC8vIFBhdGNoIGl0IHNvIFNTUi1pbXBvcnRlZCBjbGllbnQgcGFja2FnZXMgZG9uJ3QgY3Jhc2guXG4gIGlmIChcbiAgICB0eXBlb2YgZ2xvYmFsICE9PSBcInVuZGVmaW5lZFwiICYmXG4gICAgKHR5cGVvZiAoZ2xvYmFsIGFzIHVua25vd24gYXMgUmVjb3JkPHN0cmluZywgdW5rbm93bj4pLmxvY2FsU3RvcmFnZSA9PT0gXCJ1bmRlZmluZWRcIiB8fFxuICAgICAgdHlwZW9mIChnbG9iYWwgYXMgdW5rbm93biBhcyBSZWNvcmQ8c3RyaW5nLCBTdG9yYWdlPikubG9jYWxTdG9yYWdlPy5nZXRJdGVtICE9PSBcImZ1bmN0aW9uXCIpXG4gICkge1xuICAgIGNvbnN0IHN0b3JlOiBSZWNvcmQ8c3RyaW5nLCBzdHJpbmc+ID0ge31cbiAgICA7KGdsb2JhbCBhcyB1bmtub3duIGFzIFJlY29yZDxzdHJpbmcsIFN0b3JhZ2U+KS5sb2NhbFN0b3JhZ2UgPSB7XG4gICAgICBnZXRJdGVtOiAoazogc3RyaW5nKSA9PiBzdG9yZVtrXSA/PyBudWxsLFxuICAgICAgc2V0SXRlbTogKGs6IHN0cmluZywgdjogc3RyaW5nKSA9PiB7IHN0b3JlW2tdID0gdiB9LFxuICAgICAgcmVtb3ZlSXRlbTogKGs6IHN0cmluZykgPT4geyBkZWxldGUgc3RvcmVba10gfSxcbiAgICAgIGNsZWFyOiAoKSA9PiB7IGZvciAoY29uc3QgayBpbiBzdG9yZSkgZGVsZXRlIHN0b3JlW2tdIH0sXG4gICAgICBrZXk6IChpOiBudW1iZXIpID0+IE9iamVjdC5rZXlzKHN0b3JlKVtpXSA/PyBudWxsLFxuICAgICAgZ2V0IGxlbmd0aCgpIHsgcmV0dXJuIE9iamVjdC5rZXlzKHN0b3JlKS5sZW5ndGggfSxcbiAgICB9XG4gIH1cbn1cbiJdLCJuYW1lcyI6WyJyZWdpc3RlciIsImdsb2JhbCIsImxvY2FsU3RvcmFnZSIsImdldEl0ZW0iLCJzdG9yZSIsImsiLCJzZXRJdGVtIiwidiIsInJlbW92ZUl0ZW0iLCJjbGVhciIsImtleSIsImkiLCJPYmplY3QiLCJrZXlzIiwibGVuZ3RoIl0sImlnbm9yZUxpc3QiOltdLCJzb3VyY2VSb290IjoiIn0=\n//# sourceURL=webpack-internal:///(instrument)/./instrumentation.ts\n");

/***/ })

},
/******/ __webpack_require__ => { // webpackRuntimeModules
/******/ var __webpack_exec__ = (moduleId) => (__webpack_require__(__webpack_require__.s = moduleId))
/******/ var __webpack_exports__ = (__webpack_exec__("(instrument)/./instrumentation.ts"));
/******/ (_ENTRIES = typeof _ENTRIES === "undefined" ? {} : _ENTRIES).middleware_instrumentation = __webpack_exports__;
/******/ }
]);