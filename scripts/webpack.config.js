const path = require('path');
const TerserPlugin = require("terser-webpack-plugin");

const libPath = process.env['OREF0_DIST_PATH'] || './lib'

console.log('__dirname', __dirname)

module.exports = {
  mode: 'production',
  entry: path.resolve(__dirname, './src/index.js'),
  resolve: {
    alias: {
      oref0: path.resolve(libPath),
    },
  },
  output: {
    path: path.resolve(__dirname, '..', 'FreeAPS', 'Resources', 'javascript', 'bundle'),
    filename: 'oref0-bridge.js',
    library: { type: 'var', name: 'iaps' },
  },
  optimization: {
    minimize: true,
    minimizer: [new TerserPlugin({
        extractComments: false,
        parallel: true,
        terserOptions: {
            format: {
                comments: false,
            },
        },
    })],
  },
};
