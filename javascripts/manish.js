function addHeaderLinks() {
    let entry = document.getElementsByClassName('entry-content');
    if (entry.length == 0) {
        return;
    }
    entry = entry[0];
    let children = entry.querySelectorAll('h1,h2,h3,h4,h5,h6');
    for (child of children) {
        let id = child.textContent.toLowerCase().replace(/ /g, "-").replace(/[^a-z-]/g,"");
        child.id = id;

        let link = `<a href="#${id}" class="header-anchor"><span class="header-anchor-inner">§</span></a> `;
        
        child.innerHTML = link + child.innerHTML;
    }
}

$('document').ready(addHeaderLinks);
