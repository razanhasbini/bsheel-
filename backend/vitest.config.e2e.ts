import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    globals: true,
    root: './',
    include: ['**/*.e2e-spec.ts'],
    /**
     * Every e2e file boots its own Nest application, each with a pool sized
     * for a production API process. Fourteen at once asked for
     * `14 x DATABASE_POOL_MAX` connections against a server allowing 100.
     *
     * The cap belongs here rather than in `.env`: the shipped pool size is
     * right for one process serving traffic, and shrinking it to suit the
     * test runner would be tuning production for the tests. `process.env`
     * wins over the `.env` file in @nestjs/config, so this is what each
     * booted app actually uses.
     */
    env: {
      DATABASE_POOL_MAX: '5',
      DATABASE_POOL_MIN: '1',

      /**
       * The shipped throttle is 120 requests per minute per client, which is
       * right for one person using the API and wrong for a suite that drives
       * a whole fixture corpus through a freshly booted app in seconds. Each
       * e2e file boots its own application with its own in-memory throttler
       * budget, so a request-heavy suite exhausts its own allowance rather
       * than anyone else's: the keyset-pagination suite creates fifteen
       * submissions and then walks several lists three rows at a time, which
       * is a few hundred requests inside one minute and produced a 429 in
       * the middle of a page walk.
       *
       * Raised here rather than in `.env` for the same reason as the pool
       * size above — the production value is correct and should not be
       * loosened to suit the runner. Nothing in the suite asserts on
       * throttling, so no coverage is lost; a test that wants to prove the
       * limit bites should set its own.
       */
      THROTTLE_LIMIT: '2000',
    },
  },
});
