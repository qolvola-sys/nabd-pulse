import { loadEnv } from "./env.js";

loadEnv();

const { start } = await import("./server.js");
start();
