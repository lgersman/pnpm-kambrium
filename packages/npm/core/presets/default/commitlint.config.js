/*#
# default commitlint configuration
#
# this file is usually referenced in your own top level commitlint.config.js.
#
# ```
# const settings = require('@pnpmkambrium/core/presets/default/commitlint.config.js');
# module.exports = {
#   ...settings,
# };
# ```
#
# You can remove it from there depending on your needs.
#*/
const changelogConfig = require('./changelog.config.js');

module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', changelogConfig.list],
  },
};
