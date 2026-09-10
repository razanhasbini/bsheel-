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
    },
  },
});
