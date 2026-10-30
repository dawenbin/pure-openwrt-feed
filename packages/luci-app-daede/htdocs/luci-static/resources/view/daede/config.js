// SPDX-License-Identifier: Apache-2.0

'use strict';
'require uci';
'require view';
'require view.daede.backend as backend';
'require view.daede.styles as styles';
'require view.daede.widgets as widgets';

return view.extend({
	load: function() {
		return backend.detectBackend().then(function(ctx) {
			return uci.load('daed').catch(function() {}).then(function() { return ctx; });
		});
	},

	render: function(ctx) {
		const themeHref = Array.prototype.map.call(document.styleSheets, function(sheet) { return sheet.href || ''; }).join(' ');
		document.documentElement.setAttribute('data-daede-theme', /\/argon\//.test(themeHref) ? 'argon' : 'bootstrap');

		const listenAddr = uci.get('daed', 'config', 'listen_addr') || backend.BACKENDS.daed.defaultListen;
		return E('div', { 'class': 'dd-wrap dd-config-page' }, [
			E('style', {}, styles.CSS),
			widgets.renderStatusCard(ctx, listenAddr)
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
