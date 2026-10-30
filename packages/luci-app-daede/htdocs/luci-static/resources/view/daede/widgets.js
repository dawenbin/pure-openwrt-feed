// SPDX-License-Identifier: Apache-2.0

'use strict';
'require baseclass';
'require fs';
'require poll';
'require view.daede.backend as backend';

function execChecked(command, args) {
	return fs.exec(command, args || []).then(function(res) {
		if (res && res.code !== 0)
			throw new Error((res.stderr || res.stdout || ('exit ' + res.code)).trim());
		return res;
	});
}

function waitForService(be, attempts) {
	return backend.serviceStatus(be.name).then(function(state) {
		if (state.running)
			return state;
		if (attempts <= 0)
			throw new Error(_('Service did not start in time.'));
		return new Promise(function(resolve) { setTimeout(resolve, 250); })
			.then(function() { return waitForService(be, attempts - 1); });
	});
}

function renderStatusCard(ctx, listenAddr) {
	const be = ctx.backend;
	let busy = false;
	let lastError = '';
	const body = E('div', { 'id': 'dd-status-body' }, E('em', {}, _('Collecting data…')));
	const card = E('div', { 'class': 'dd-card dd-status-card' }, [
		E('h4', { 'class': 'dd-card-title' }, _('Service Status')),
		body
	]);

	const action = function(button, command, failure) {
		button.addEventListener('click', function(ev) {
			ev.preventDefault();
			if (busy) return;
			busy = true;
			button.disabled = true;
			lastError = '';
			execChecked(be.initd, [command])
				.then(function() { return waitForService(be, 80); })
				.catch(function(e) { lastError = failure.format(e.message || e); })
				.finally(function() {
					busy = false;
					return refresh();
				});
		});
		return button;
	};

	const render = function(state) {
		while (body.firstChild) body.removeChild(body.firstChild);

		const badge = state.running
			? E('span', { 'class': 'dd-badge dd-badge-run' }, [ E('span', { 'class': 'dd-badge-dot' }), _('RUNNING') ])
			: E('span', { 'class': 'dd-badge dd-badge-stop' }, [ E('span', { 'class': 'dd-badge-dot' }), _('STOPPED') ]);
		const meta = [
			E('span', { 'class': 'dd-meta' }, [ E('span', { 'class': 'dd-meta-label' }, _('Backend')), be.name ])
		];
		if (state.running && state.pid)
			meta.push(E('span', { 'class': 'dd-meta' }, [ E('span', { 'class': 'dd-meta-label' }, 'PID'), state.pid ]));

		body.appendChild(E('div', { 'class': 'dd-status-row' }, [
			badge,
			E('span', { 'class': 'dd-grow' }),
			E('span', { 'class': 'dd-meta dd-err', 'style': lastError ? '' : 'display:none' }, lastError)
		]));
		body.appendChild(E('div', { 'class': 'dd-status-meta' }, meta));

		const actions = [];
		if (state.running) {
			const port = (listenAddr || be.defaultListen).split(':').slice(-1)[0];
			actions.push(E('a', {
				'class': 'cbi-button cbi-button-action',
				'href': 'http://%s:%s'.format(window.location.hostname, port),
				'target': '_blank',
				'rel': 'noreferrer noopener'
			}, _('Open WebUI')));
			actions.push(action(E('button', { 'class': 'cbi-button cbi-button-positive' }, _('Restart')),
				'restart', _('Restart failed: %s')));
		} else {
			actions.push(action(E('button', { 'class': 'cbi-button cbi-button-positive' }, _('Start')),
				'start', _('Toggle failed: %s')));
		}
		body.appendChild(E('div', { 'class': 'dd-actions' }, actions));
	};

	const refresh = function() {
		if (busy)
			return Promise.resolve();
		return backend.serviceStatus(be.name).then(render);
	};

	poll.add(refresh);
	refresh();
	return card;
}

return baseclass.extend({
	renderStatusCard: renderStatusCard
});
