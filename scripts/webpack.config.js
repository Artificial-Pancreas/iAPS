const path = require('path');
const TerserPlugin = require("terser-webpack-plugin");

const libPath = process.env['OREF0_DIST_PATH'] || './lib'

console.log('__dirname', __dirname)

// const mode = 'development'
const mode = 'production'

module.exports = {
  mode,
  entry: path.resolve(__dirname, '../FreeAPS/Resources/javascript/bridge/index.js'),
  resolve: {
    alias: {
      oref0: path.resolve(libPath),
      prepare: path.resolve(__dirname, '../FreeAPS/Resources/javascript/prepare'),
      autoisf: path.resolve(__dirname, '../FreeAPS/Resources/javascript/autoisf'),
    },
  },
  output: {
    path: path.resolve(__dirname, '..', 'FreeAPS', 'Resources', 'javascript', 'bundle'),
    filename: 'oref0-bridge.js',
    library: { type: 'var', name: 'iaps' },
  },
  optimization: {
    minimize: mode !== 'development',
    minimizer: mode !== 'development' ? [new TerserPlugin({
        extractComments: false,
        parallel: true,
        terserOptions: {
            format: {
                comments: false,
            },
        },
    })] : [],
  },
};
