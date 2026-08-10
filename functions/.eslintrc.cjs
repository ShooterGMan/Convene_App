module.exports = {
  root: true,
  env: {
    es2021: true,
    node: true,
  },
  parser: '@typescript-eslint/parser',
  plugins: ['@typescript-eslint'],
  extends: ['eslint:recommended'],
  ignorePatterns: ['lib/**', 'node_modules/**'],
  rules: {
    'no-console': 'off',
    'no-debugger': 'error',
    'no-duplicate-imports': 'error',
    // TypeScript resolves namespaces such as FirebaseFirestore; its compiler
    // is the authoritative undefined-name check for this project.
    'no-undef': 'off',
    'no-unused-vars': 'off',
    '@typescript-eslint/no-unused-vars': 'error',
  },
};
