module.exports = {
  root: true,
  env: { node: true, es2022: true, jest: true },
  extends: ['eslint:recommended', 'plugin:security/recommended'],
  plugins: ['security'],
  parserOptions: { ecmaVersion: 2022 },
};
