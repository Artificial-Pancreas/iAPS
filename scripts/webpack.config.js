const path = require('path');
const TerserPlugin = require("terser-webpack-plugin");

const libPath = process.env['OREF0_DIST_PATH'] || './lib'

module.exports = {
  mode: 'production',
  entry: {
    iob: path.resolve(libPath, 'iob/index.js'),
    meal: path.resolve(libPath, 'meal/index.js'),
    determineBasal: path.resolve(libPath, 'determine-basal/determine-basal.js'),
    glucoseGetLast: path.resolve(libPath, 'glucose-get-last.js'),
    basalSetTemp: path.resolve(libPath, 'basal-set-temp.js'),
    autosens: path.resolve(libPath, 'determine-basal/autosens.js'),
    profile: path.resolve(libPath, 'profile/index.js'),
    autotunePrep: path.resolve(libPath, 'autotune-prep/index.js'),
    autotuneCore: path.resolve(libPath, 'autotune/index.js')
  },
  output: {
    path: path.resolve(__dirname, '..', 'FreeAPS', 'Resources', 'javascript', 'bundle'),
    filename: (pathData) => {
        return pathData.chunk.name.replace(/[A-Z]/g, function(match) {
            return '-' + match.toLowerCase();
        }) + '.js';
    },
    library: {
        type: 'var',
        name: 'freeaps_[name]'
    }
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
