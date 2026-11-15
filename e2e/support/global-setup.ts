import { seed, restartRails, resetCounters } from "./stack";

export default async function globalSetup() {
  if (process.env.BASE_URL) return; // smoke contra outro ambiente: sem seed nem restart
  console.log(seed(process.env.E2E_SEED ?? "basico"));
  resetCounters();
  await restartRails(`http://127.0.0.1:${process.env.E2E_PORT ?? 3555}`); // zera o rate limit do login
}
