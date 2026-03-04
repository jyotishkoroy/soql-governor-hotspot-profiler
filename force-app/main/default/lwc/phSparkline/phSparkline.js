import { LightningElement, api } from 'lwc';

export default class PhSparkline extends LightningElement {
    @api values = [];

    get points() {
        const vals = (this.values || []).map(v => Number(v) || 0);
        if (!vals.length) return '';
        const min = Math.min(...vals);
        const max = Math.max(...vals);
        const span = (max - min) || 1;

        const w = 120;
        const h = 30;
        const step = vals.length === 1 ? w : (w / (vals.length - 1));

        return vals.map((v, i) => {
            const x = i * step;
            const y = h - ((v - min) / span) * (h - 4) - 2;
            return `${x.toFixed(1)},${y.toFixed(1)}`;
        }).join(' ');
    }
}
