<template>
  <router-view :key="String($route.params.id ?? '')" />
</template>
