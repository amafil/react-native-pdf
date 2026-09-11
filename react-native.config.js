module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import org.wonday.pdf.RNPDFPackage;',
        packageInstance: 'new RNPDFPackage()',
      },
    },
  },
};
